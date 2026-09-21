require 'active_record'
require 'json'
require_relative '../../db/migrate/20260921010000_repair_duplicate_phone_contacts'

RSpec.describe RepairDuplicatePhoneContacts do
  let(:db) { ActiveRecord::Base.connection }

  around do |example|
    db.transaction do
      db.execute <<~SQL.squish
        CREATE TABLE contacts(id bigint PRIMARY KEY,account_id bigint,phone_number text,email text,name text,
          additional_attributes jsonb DEFAULT '{}',custom_attributes jsonb DEFAULT '{}',blocked boolean DEFAULT false);
        CREATE UNIQUE INDEX email_identity ON contacts(email,account_id);
        CREATE TABLE inboxes(id bigint PRIMARY KEY,account_id bigint,lock_to_single_conversation boolean);
        CREATE TABLE contact_inboxes(id bigint PRIMARY KEY,contact_id bigint,inbox_id bigint,source_id text);
        CREATE UNIQUE INDEX inbox_identity ON contact_inboxes(inbox_id,source_id);
        CREATE TABLE notification_subscriptions(id bigint PRIMARY KEY);
        CREATE TABLE conversations(id bigint PRIMARY KEY,account_id bigint,inbox_id bigint,contact_id bigint,contact_inbox_id bigint,
          display_id bigint,"group" boolean DEFAULT false,group_source_id text,created_at timestamp DEFAULT now(),status integer DEFAULT 0);
        CREATE TABLE messages(id bigint PRIMARY KEY,conversation_id bigint,sender_type text,sender_id bigint,content text);
        CREATE TABLE notes(id bigint PRIMARY KEY,contact_id bigint,content text);
        CREATE TABLE users(id bigint PRIMARY KEY,ui_settings jsonb);
        CREATE TABLE conversation_participants(id bigint PRIMARY KEY,conversation_id bigint,user_id bigint);
        INSERT INTO inboxes VALUES(1,1,false),(2,2,false);
        INSERT INTO contacts(id,account_id,phone_number,name) VALUES(1,1,'+55 (66) 99985-7544','Old'),(2,1,'5566999857544','New');
        INSERT INTO contact_inboxes VALUES(10,1,1,'5566999857544'),(11,2,1,'123@lid');
        INSERT INTO conversations(id,account_id,inbox_id,contact_id,contact_inbox_id,display_id,created_at)
        VALUES(20,1,1,1,10,100,'2026-01-01'),(21,1,1,2,11,101,'2026-02-01');
        INSERT INTO messages VALUES(30,20,'Contact',1,'old'),(31,21,'Contact',2,'new');
        INSERT INTO notes VALUES(40,2,'preserve note');
      SQL
      example.run
      raise ActiveRecord::Rollback
    end
  end

  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    skip 'Standalone integration test: use viper_identity_fixture_test' unless ENV['PGDATABASE'] == 'viper_identity_fixture_test'

    ActiveRecord::Base.establish_connection(adapter: 'postgresql', host: ENV.fetch('PGHOST'), username: ENV.fetch('PGUSER'),
                                            password: ENV.fetch('PGPASSWORD'), database: ENV.fetch('PGDATABASE'))
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

  it 'keeps the lowest ID and preserves separate conversations, phone and LID aliases, messages and notes' do
    described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
    expect(db.select_rows('SELECT id,name FROM contacts')).to eq([[1, 'Old']])
    expect(db.select_rows('SELECT id,contact_id,source_id FROM contact_inboxes ORDER BY id')).to eq([[10, 1, '5566999857544'], [11, 1, '123@lid']])
    expect(db.select_values('SELECT id FROM conversations ORDER BY id')).to eq([20, 21])
    expect(db.select_rows('SELECT id,conversation_id,sender_id,content FROM messages ORDER BY id')).to eq([[30, 20, 1, 'old'], [31, 21, 1, 'new']])
    expect(db.select_value('SELECT contact_id FROM notes')).to eq(1)
    count = db.select_value('SELECT count(*) FROM phone_contact_repair_audits')
    described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
    expect(db.select_value('SELECT count(*) FROM phone_contact_repair_audits')).to eq(count)
  end

  it 'never joins different accounts or infers country code or a Brazilian ninth digit' do
    db.execute <<~SQL.squish
      INSERT INTO contacts(id,account_id,phone_number) VALUES(3,2,'5566999857544'),(4,1,'66999857544'),(5,1,'556699857544');
    SQL
    described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
    expect(db.select_values('SELECT id FROM contacts ORDER BY id')).to eq([1, 3, 4, 5])
  end

  it 'ignores empty, malformed, too short and too long numbers' do
    db.execute <<~SQL.squish
      INSERT INTO contacts(id,account_id,phone_number) VALUES(3,1,''),(4,1,''),(5,1,NULL),(6,1,NULL),
        (7,1,'abc5566999857544'),(8,1,'123'),(9,1,'123'),(10,1,'1234567890123456'),(11,1,'1234567890123456');
    SQL
    described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
    expect(db.select_value('SELECT count(*) FROM contacts')).to eq(10)
  end

  it 'does not consolidate group profiles using an inherited participant phone' do
    db.execute "UPDATE contact_inboxes SET source_id='123@g.us' WHERE id=11"
    described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
    expect(db.select_values('SELECT id FROM contacts ORDER BY id')).to eq([1, 2])
  end

  it 'keeps the latest conversation and its participants only when the inbox enables single conversation' do
    db.execute <<~SQL.squish
      UPDATE inboxes SET lock_to_single_conversation=true WHERE id=1;
      INSERT INTO conversation_participants VALUES(1,20,5),(2,21,6);
    SQL
    described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
    expect(db.select_values('SELECT id FROM conversations')).to eq([21])
    expect(db.select_values('SELECT conversation_id FROM messages ORDER BY id')).to eq([21, 21])
    expect(db.select_values('SELECT user_id FROM conversation_participants')).to eq([6])
    expect(db.select_value("SELECT original_row->>'contact_id' FROM phone_contact_repair_audits WHERE source_table='conversations' AND source_id=21"))
      .to eq('2')
  end

  it 'rolls back the entire contact repair if historical SLA records prevent conversation consolidation' do
    db.execute <<~SQL.squish
      UPDATE inboxes SET lock_to_single_conversation=true;
      CREATE TABLE applied_slas(id bigint PRIMARY KEY,conversation_id bigint);
      INSERT INTO applied_slas VALUES(1,20);
    SQL
    expect do
      db.transaction(requires_new: true) do
        described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
      end
    end.to raise_error(Conversations::HistoryMerge::Conflict)
    expect(db.select_values('SELECT id FROM contacts ORDER BY id')).to eq([1, 2])
    expect(db.select_value('SELECT contact_id FROM contact_inboxes WHERE id=11')).to eq(2)
    expect(db.table_exists?('phone_contact_repair_audits')).to be(false)
  end

  it 'complements missing oldest contact data without losing newer email under its unique index' do
    db.execute "UPDATE contacts SET email='new@example.com',blocked=true WHERE id=2"
    described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
    expect(db.select_rows('SELECT id,email,blocked FROM contacts')).to eq([[1, 'new@example.com', true]])
    expect(db.indexes('contacts').find { |index| index.name == 'email_identity' }.unique).to be(true)
  end
end
