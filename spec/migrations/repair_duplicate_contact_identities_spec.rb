# Standalone PostgreSQL integration specs: never load Rails or production callbacks.
require 'active_record'
require 'json'
require_relative '../../db/migrate/20260919010000_repair_duplicate_contact_identities'

RSpec.describe RepairDuplicateContactIdentities do
  let(:db) { ActiveRecord::Base.connection }

  around do |example|
    db.transaction do
      db.execute <<~SQL.squish
        CREATE TABLE contacts(id bigint PRIMARY KEY, account_id bigint, email text, name text,
          phone_number text, blocked boolean DEFAULT false, additional_attributes jsonb DEFAULT '{}', custom_attributes jsonb DEFAULT '{}');
        CREATE TABLE inboxes(id bigint PRIMARY KEY, account_id bigint);
        CREATE TABLE contact_inboxes(id bigint PRIMARY KEY,contact_id bigint,inbox_id bigint,source_id text,
          additional_attributes jsonb DEFAULT '{}');
        CREATE TABLE conversations(id bigint PRIMARY KEY,contact_id bigint,contact_inbox_id bigint);
        CREATE TABLE messages(id bigint PRIMARY KEY,sender_id bigint,sender_type text,content text);
        CREATE TABLE notes(id bigint PRIMARY KEY,contact_id bigint,content text);
        CREATE TABLE group_contacts(id bigint PRIMARY KEY,contact_id bigint,conversation_id bigint,metadata jsonb DEFAULT '{}');
        CREATE UNIQUE INDEX group_membership ON group_contacts(conversation_id,contact_id);
        CREATE TABLE notification_subscriptions(id bigint PRIMARY KEY,user_id bigint,identifier text,
          subscription_type integer,subscription_attributes jsonb DEFAULT '{}',updated_at timestamp DEFAULT now());
        INSERT INTO inboxes VALUES(1,1),(2,2);
      SQL
      example.run
      raise ActiveRecord::Rollback
    end
  end

  # Connection only; every fixture and DDL statement is rolled back per example.
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    skip 'Standalone integration test: use viper_identity_fixture_test (see docs)' unless ENV['PGDATABASE'] == 'viper_identity_fixture_test'

    ActiveRecord::Base.establish_connection(adapter: 'postgresql', host: ENV.fetch('PGHOST'),
                                            username: ENV.fetch('PGUSER'), password: ENV.fetch('PGPASSWORD'),
                                            database: ENV.fetch('PGDATABASE'))
    ActiveRecord::Migration.verbose = false
  end

  it 'only prepares audit storage on upgrade, preserving every existing row and index' do
    tables = db.tables
    before_rows = tables.index_with do |table|
      db.select_values("SELECT to_jsonb(t)::text FROM #{db.quote_table_name(table)} t ORDER BY to_jsonb(t)::text")
    end
    before_indexes = db.select_rows("SELECT indexname,indexdef FROM pg_indexes WHERE schemaname='public' ORDER BY indexname")
    migration = described_class.new
    expect(migration).not_to receive(:repair!)
    2.times { migration.migrate(:up) }
    tables.each do |table|
      expect(db.select_values("SELECT to_jsonb(t)::text FROM #{db.quote_table_name(table)} t ORDER BY to_jsonb(t)::text")).to eq(before_rows[table])
    end
    after_indexes = db.select_rows("SELECT indexname,indexdef FROM pg_indexes WHERE schemaname='public' ORDER BY indexname")
    expect(before_indexes - after_indexes).to be_empty
  end

  it 'requires explicit confirmation for a manual repair' do
    expect { described_class.new.repair!(confirmation: 'no') }.to raise_error(ArgumentError)
  end

  it 'merges transitive duplicates into the lowest ID without changing message/conversation IDs' do
    db.execute <<~SQL.squish
      INSERT INTO contacts(id,account_id,email,name) VALUES(1,1,'same@example.com','Old'),(2,1,'SAME@example.com','New'),(3,1,'other@example.com','Other');
      INSERT INTO contact_inboxes(id,contact_id,inbox_id,source_id) VALUES(10,2,1,'abc'),(11,3,1,'abc');
      INSERT INTO conversations VALUES(20,3,11);
      INSERT INTO messages VALUES(30,3,'Contact','preserve'),(31,3,'User','agent');
      INSERT INTO notes VALUES(40,2,'note');
    SQL
    described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
    expect(db.select_values('SELECT id FROM contacts')).to eq([1])
    expect(db.select_value('SELECT name FROM contacts WHERE id=1')).to eq('Old')
    expect(db.select_rows('SELECT * FROM conversations')).to eq([[20, 1, 10]])
    expect(db.select_rows('SELECT id,sender_id,content FROM messages ORDER BY id')).to eq([[30, 1, 'preserve'], [31, 3, 'agent']])
    expect(db.select_value('SELECT contact_id FROM notes')).to eq(1)
    count = db.select_value('SELECT count(*) FROM contact_identity_repair_audits')
    described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
    expect(db.select_value('SELECT count(*) FROM contact_identity_repair_audits')).to eq(count)
  end

  it 'keeps accounts separate and clears LID emails with their original value archived' do
    db.execute "INSERT INTO contacts(id,account_id,email) VALUES(1,1,'123@lid'),(2,2,'123@lid')"
    described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
    expect(db.select_value('SELECT count(*) FROM contacts')).to eq(2)
    expect(db.select_value('SELECT count(email) FROM contacts')).to eq(0)
    expect(db.select_values("SELECT original_row->>'email' FROM contact_identity_repair_audits ORDER BY source_id")).to eq(['123@lid', '123@lid'])
  end

  it 'preserves group metadata and restrictive blocked state when memberships collide' do
    db.execute <<~SQL.squish
      INSERT INTO contacts(id,account_id,email,blocked) VALUES(1,1,'a@b.com',false),(2,1,'a@b.com',true);
      INSERT INTO group_contacts VALUES(1,1,5,'{"old":true}'),(2,2,5,'{"new":true}');
    SQL
    described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
    expect(db.select_value('SELECT blocked FROM contacts')).to be(true)
    expect(db.select_value('SELECT count(*) FROM group_contacts')).to eq(1)
    expect(JSON.parse(db.select_value('SELECT metadata FROM group_contacts'))).to eq('old' => true, 'new' => true)
  end

  it 'keeps the latest keys for the same notification user and device' do
    db.execute <<~SQL.squish
      INSERT INTO notification_subscriptions(id,user_id,identifier,subscription_type,subscription_attributes,updated_at)
      VALUES(1,10,'device',1,'{"key":"old"}','2026-01-01'),(2,10,'device',1,'{"key":"new"}','2026-02-01');
    SQL
    described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
    expect(db.select_values('SELECT id FROM notification_subscriptions')).to eq([2])
    expect(db.select_value("SELECT original_row->'subscription_attributes'->>'key' FROM contact_identity_repair_audits")).to eq('old')
  end

  it 'preserves attachment blobs and labels while collapsing identical join rows' do
    db.execute <<~SQL.squish
      CREATE TABLE active_storage_attachments(id bigint PRIMARY KEY,record_id bigint,record_type text,name text,blob_id bigint);
      CREATE UNIQUE INDEX attachment_identity ON active_storage_attachments(record_type,record_id,name,blob_id);
      CREATE TABLE taggings(id bigint PRIMARY KEY,taggable_id bigint,taggable_type text,tag_id bigint,context text,tagger_id bigint,tagger_type text);
      CREATE TABLE tags(id bigint PRIMARY KEY,taggings_count integer);
      INSERT INTO contacts(id,account_id,email) VALUES(1,1,'a@b.com'),(2,1,'a@b.com');
      INSERT INTO active_storage_attachments VALUES(1,1,'Contact','avatar',10),(2,2,'Contact','avatar',10),(3,2,'Contact','avatar',11);
      INSERT INTO tags VALUES(1,2);
      INSERT INTO taggings VALUES(1,1,'Contact',1,'labels',NULL,NULL),(2,2,'Contact',1,'labels',NULL,NULL);
    SQL
    described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
    expect(db.select_rows('SELECT record_id,blob_id FROM active_storage_attachments ORDER BY blob_id')).to eq([[1, 10], [1, 11]])
    expect(db.select_value('SELECT count(*) FROM taggings')).to eq(1)
    expect(db.select_value('SELECT taggings_count FROM tags')).to eq(1)
    expect(db.select_value("SELECT count(*) FROM contact_identity_repair_audits WHERE source_table='active_storage_attachments'")).to eq(2)
  end

  it 'aborts and rolls back all changes if a notification belongs to different users' do
    db.execute <<~SQL.squish
      INSERT INTO contacts(id,account_id,email) VALUES(1,1,'a@b.com'),(2,1,'a@b.com');
      INSERT INTO notification_subscriptions(id,user_id,identifier,subscription_type) VALUES(1,10,'device',1),(2,11,'device',1);
    SQL
    expect do
      db.transaction(requires_new: true) do
        described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
      end
    end.to raise_error(/different users/)
    expect(db.select_value('SELECT count(*) FROM contacts')).to eq(2)
    expect(db.table_exists?('contact_identity_repair_audits')).to be(false)
  end

  it 'refuses a contact inbox crossing account boundaries' do
    db.execute <<~SQL.squish
      INSERT INTO contacts(id,account_id,email) VALUES(1,1,'a@b.com');
      INSERT INTO contact_inboxes(id,contact_id,inbox_id,source_id) VALUES(1,1,2,'abc');
    SQL
    expect { described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS') }.to raise_error(/Cross-account/)
  end

  it 'removes existing incomplete unique indexes before touching duplicate rows and rebuilds full constraints' do
    # Partial indexes safely model incomplete coverage without corrupting PostgreSQL.
    db.execute <<~SQL.squish
      INSERT INTO contacts(id,account_id,email) VALUES(1,1,'same@example.com'),(2,1,'same@example.com');
      INSERT INTO contact_inboxes(id,contact_id,inbox_id,source_id) VALUES(10,1,1,'same'),(11,2,1,'same');
      CREATE UNIQUE INDEX uniq_email_per_account_contact ON contacts(email,account_id) WHERE id=1;
      CREATE UNIQUE INDEX index_contact_inboxes_on_inbox_id_and_source_id ON contact_inboxes(inbox_id,source_id) WHERE id=10;
      CREATE UNIQUE INDEX index_notification_subscriptions_on_identifier ON notification_subscriptions(identifier);
    SQL
    allow(db).to receive(:execute).and_wrap_original do |original, sql, *args, **kwargs|
      if sql.match?(/\AUPDATE (?:"?contacts"?|"?contact_inboxes"?)\b/i)
        expect(db.indexes('contacts').map(&:name)).not_to include('uniq_email_per_account_contact')
        expect(db.indexes('contact_inboxes').map(&:name)).not_to include('index_contact_inboxes_on_inbox_id_and_source_id')
      end
      original.call(sql, *args, **kwargs)
    end

    described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')

    expect(db.select_values('SELECT id FROM contacts')).to eq([1])
    expect(db.select_values('SELECT id FROM contact_inboxes')).to eq([10])
    described_class::INDEXES.each do |name, (table, _columns)|
      index = db.indexes(table).find { |item| item.name == name }
      expect(index.unique).to be(true)
      expect(index.where).to be_nil
    end
  end

  it 'restores existing indexes and rows when repair aborts after dropping indexes' do
    db.execute <<~SQL.squish
      INSERT INTO contacts(id,account_id,email) VALUES(1,1,'same@example.com'),(2,1,'same@example.com');
      CREATE UNIQUE INDEX uniq_email_per_account_contact ON contacts(email,account_id) WHERE id=1;
      INSERT INTO notification_subscriptions(id,user_id,identifier,subscription_type) VALUES(1,10,'device',1),(2,11,'device',1);
    SQL
    expect do
      db.transaction(requires_new: true) do
        described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
      end
    end.to raise_error(/different users/)
    expect(db.select_values('SELECT id FROM contacts ORDER BY id')).to eq([1, 2])
    expect(db.indexes('contacts').find { |index| index.name == 'uniq_email_per_account_contact' }.where).to be_present
    expect(db.table_exists?('contact_identity_repair_audits')).to be(false)
  end
end
