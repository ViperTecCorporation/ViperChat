require 'rails_helper'

RSpec.describe ConversationBuilder do
  let(:account) { create(:account) }
  let(:meta_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+556696222471',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:uno_channel) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5566996222471',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:contact) { create(:contact, account: account, phone_number: '+5566996269251') }
  let(:primary_alias) { create(:contact_inbox, contact: contact, inbox: meta_channel.inbox, source_id: '556696269251') }
  let(:params) { ActionController::Parameters.new }
  let(:builder) { described_class.new(params: params, contact_inbox: primary_alias) }

  context 'with an active pair' do
    let(:link) do
      WhatsappInboxLink.create!(account: account, primary_inbox: meta_channel.inbox, secondary_inbox: uno_channel.inbox,
                                default_provider: 'unoapi', enabled: true)
    end

    before { link }

    it 'performs the reuse lookup under the principal contact-inbox lock' do
      existing = create(:conversation, account: account, inbox: meta_channel.inbox, contact: contact, contact_inbox: primary_alias)
      expect(primary_alias).to receive(:with_lock).and_call_original

      expect { expect(builder.perform.id).to eq(existing.id) }.not_to change(Conversation, :count)
    end

    it 'locks creation as well and reuses it on the next compose' do
      expect(primary_alias).to receive(:with_lock).twice.and_call_original
      first = builder.perform

      expect { expect(builder.perform.id).to eq(first.id) }.not_to change(Conversation, :count)
    end

    it 'finds active conversations on another alias of the same principal contact' do
      other_alias = create(:contact_inbox, inbox: meta_channel.inbox, contact: contact, source_id: '5566996269251')
      existing = create(:conversation, account: account, inbox: meta_channel.inbox, contact: contact, contact_inbox: other_alias)

      expect { expect(builder.perform.id).to eq(existing.id) }.not_to change(Conversation, :count)
      expect(existing.reload.contact_inbox_id).to eq(other_alias.id)
    end

    it 'reuses an older active conversation even if the newest one is resolved' do
      existing = create(:conversation, account: account, inbox: meta_channel.inbox, contact: contact, contact_inbox: primary_alias,
                                       status: :pending, created_at: 2.days.ago)
      create(:conversation, account: account, inbox: meta_channel.inbox, contact: contact, contact_inbox: primary_alias, status: :resolved)

      expect(builder.perform.id).to eq(existing.id)
    end

    it 'keeps group creation physical and outside the direct-contact locking branch' do
      group_contact = create(:contact, account: account, phone_number: nil, email: '120363000000001@g.us')
      group_alias = create(:contact_inbox, contact: group_contact, inbox: uno_channel.inbox, source_id: group_contact.email)
      expect(group_alias).not_to receive(:with_lock)

      result = described_class.new(params: params, contact_inbox: group_alias).perform

      expect(result).to have_attributes(inbox_id: uno_channel.inbox.id, contact_inbox_id: group_alias.id)
    end
  end

  it 'retains non-unique unlinked creation even if an active conversation exists' do
    meta_channel.inbox.update!(lock_to_single_conversation: false)
    existing = create(:conversation, account: account, inbox: meta_channel.inbox, contact: contact, contact_inbox: primary_alias)
    expect(primary_alias).not_to receive(:with_lock)

    expect { expect(builder.perform.id).not_to eq(existing.id) }.to change(Conversation, :count).by(1)
  end

  it 'retains unique unlinked reuse without introducing linked-branch reopening' do
    meta_channel.inbox.update!(lock_to_single_conversation: true)
    existing = create(:conversation, account: account, inbox: meta_channel.inbox, contact: contact, contact_inbox: primary_alias, status: :resolved)
    expect(primary_alias).not_to receive(:with_lock)

    expect(builder.perform.id).to eq(existing.id)
    expect(existing.reload.status).to eq('resolved')
  end
end
