require 'active_record'
require 'json'
require_relative '../../db/migrate/20260919020000_reconcile_repaired_single_conversations'

RSpec.describe ReconcileRepairedSingleConversations do
  let(:db) { ActiveRecord::Base.connection }

  around do |example|
    db.transaction do
      db.execute <<~SQL.squish
        CREATE TABLE contacts(id bigint PRIMARY KEY);
        CREATE TABLE inboxes(id bigint PRIMARY KEY,account_id bigint,lock_to_single_conversation boolean);
        CREATE TABLE contact_inboxes(id bigint PRIMARY KEY,contact_id bigint,inbox_id bigint,source_id text);
        CREATE TABLE notification_subscriptions(id bigint PRIMARY KEY);
        CREATE TABLE contact_identity_repair_audits(id bigint PRIMARY KEY,source_table text,source_id bigint,retained_id bigint,original_row jsonb);
        CREATE TABLE conversations(id bigint PRIMARY KEY,account_id bigint,inbox_id bigint,contact_id bigint,contact_inbox_id bigint,
          display_id bigint,"group" boolean DEFAULT false,group_source_id text,created_at timestamp DEFAULT now(),
          last_activity_at timestamp DEFAULT now(),status integer DEFAULT 0);
        CREATE TABLE messages(id bigint PRIMARY KEY,conversation_id bigint,content text);
        CREATE TABLE scheduled_messages(id bigint PRIMARY KEY,conversation_id bigint,target_conversation_id bigint);
        CREATE TABLE notifications(id bigint PRIMARY KEY,primary_actor_type text,primary_actor_id bigint);
        CREATE TABLE conversation_participants(id bigint PRIMARY KEY,conversation_id bigint,user_id bigint);
        CREATE UNIQUE INDEX participant_identity ON conversation_participants(conversation_id,user_id);
        CREATE TABLE users(id bigint PRIMARY KEY,ui_settings jsonb);
        INSERT INTO contacts VALUES(1),(2);
        INSERT INTO inboxes VALUES(1,1,true),(2,1,false),(3,2,true);
        INSERT INTO contact_inboxes VALUES(1,1,1,'canonical'),(2,1,2,'other'),(3,2,3,'canonical');
        INSERT INTO contact_identity_repair_audits VALUES(1,'contacts',9,1,'{}'),(2,'contacts',10,2,'{}');
        INSERT INTO conversations(id,account_id,inbox_id,contact_id,contact_inbox_id,display_id,last_activity_at)
        VALUES(10,1,1,1,1,100,'2026-01-01'),(11,1,1,1,1,101,'2026-02-01'),
        (20,1,2,1,2,200,'2026-01-01'),(21,1,2,1,2,201,'2026-02-01'),(30,2,3,2,3,100,'2026-01-01');
      SQL
      example.run
      raise ActiveRecord::Rollback
    end
  end

  # Connection only; all fixtures and DDL are rolled back per example.
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    skip 'Standalone integration test: use viper_identity_fixture_test' unless ENV['PGDATABASE'] == 'viper_identity_fixture_test'

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

  it 'merges only enabled inboxes, preserving message IDs and remapping dependent records and preferences' do
    db.execute <<~SQL.squish
      INSERT INTO messages VALUES(1,10,'old'),(2,11,'new'),(3,20,'disabled');
      INSERT INTO scheduled_messages VALUES(1,10,10);
      INSERT INTO notifications VALUES(1,'Conversation',10),(2,'Contact',10);
      INSERT INTO conversation_participants VALUES(1,10,5),(2,11,5),(3,10,6);
      INSERT INTO users VALUES(1,'{"pinned_conversations":{"1":[100,101],"2":[100]},"archived_conversations":{"1":[100]}}');
    SQL
    described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
    expect(db.select_values('SELECT id FROM conversations ORDER BY id')).to eq([11, 20, 21, 30])
    expect(db.select_rows('SELECT * FROM messages ORDER BY id')).to eq([[1, 11, 'old'], [2, 11, 'new'], [3, 20, 'disabled']])
    expect(db.select_rows('SELECT * FROM scheduled_messages')).to eq([[1, 11, 11]])
    expect(db.select_values('SELECT primary_actor_id FROM notifications ORDER BY id')).to eq([11, 10])
    expect(db.select_rows('SELECT conversation_id,user_id FROM conversation_participants ORDER BY user_id')).to eq([[11, 5]])
    settings = JSON.parse(db.select_value('SELECT ui_settings FROM users'))
    expect(settings).to include('pinned_conversations' => { '1' => [101], '2' => [100] }, 'archived_conversations' => { '1' => [] })
    count = db.select_value('SELECT count(*) FROM conversation_identity_repair_audits')
    described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
    expect(db.select_value('SELECT count(*) FROM conversation_identity_repair_audits')).to eq(count)
  end

  it 'does nothing to conversations when the single-conversation option is disabled' do
    db.execute 'UPDATE inboxes SET lock_to_single_conversation=false'
    described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
    expect(db.select_values('SELECT id FROM conversations ORDER BY id')).to eq([10, 11, 20, 21, 30])
    expect(db.select_value('SELECT count(*) FROM conversation_identity_repair_audits')).to eq(0)
  end

  it 'does not merge different groups or contacts outside the repair scope' do
    db.execute <<~SQL.squish
      UPDATE conversations SET "group"=true,group_source_id=id::text WHERE id IN (10,11);
      INSERT INTO contacts VALUES(3);
      INSERT INTO contact_inboxes VALUES(4,3,1,'not-repaired');
      INSERT INTO conversations(id,account_id,inbox_id,contact_id,contact_inbox_id,display_id)
      VALUES(40,1,1,3,4,400),(41,1,1,3,4,401);
    SQL
    described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
    expect(db.select_value('SELECT count(*) FROM conversations')).to eq(7)
  end

  it 'keeps the newest created conversation even if the old canonical alias was active more recently' do
    db.execute <<~SQL.squish
      INSERT INTO contact_inboxes VALUES(4,1,1,'123@lid');
      UPDATE conversations SET contact_inbox_id=4 WHERE id=11;
      UPDATE conversations SET created_at='2025-01-01',last_activity_at='2026-03-01',status=1 WHERE id=10;
      UPDATE conversations SET created_at='2025-02-01',status=0 WHERE id=11;
    SQL
    described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
    expect(db.select_values('SELECT id FROM conversations WHERE inbox_id=1')).to eq([11])
    expect(db.select_rows('SELECT status,last_activity_at::date::text FROM conversations WHERE id=11')).to eq([[0, '2026-02-01']])
  end

  it 'rolls back rather than discarding conflicting unique business records' do
    db.execute <<~SQL.squish
      CREATE TABLE applied_slas(id bigint PRIMARY KEY,conversation_id bigint,policy_id bigint);
      CREATE UNIQUE INDEX sla_identity ON applied_slas(conversation_id,policy_id);
      INSERT INTO applied_slas VALUES(1,10,1),(2,11,1);
      INSERT INTO messages VALUES(1,10,'preserve');
    SQL
    expect do
      db.transaction(requires_new: true) do
        described_class.new.repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')
      end
    end.to raise_error(Conversations::HistoryMerge::Conflict)
    expect(db.select_value('SELECT count(*) FROM conversations')).to eq(5)
    expect(db.select_value('SELECT conversation_id FROM messages')).to eq(10)
    expect(db.table_exists?('conversation_identity_repair_audits')).to be(false)
  end
end
