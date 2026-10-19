require 'rails_helper'

RSpec.describe Whatsapp::ContactReconciliationService do
  let(:account) { create(:account) }
  let(:meta) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+556696222471',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:uno) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5566996222471',
                              sync_templates: false, validate_provider_config: false)
  end
  let!(:link) do
    WhatsappInboxLink.create!(account: account, primary_inbox: uno.inbox, secondary_inbox: meta.inbox, enabled: true, default_provider: 'unoapi')
  end
  let!(:canonical) { create(:contact, account: account, name: 'Contato antigo preservado', phone_number: '+5566996092506', created_at: 2.years.ago) }
  let!(:legacy) { create(:contact, account: account, name: 'BR.1898499644457061', phone_number: nil, bsuid: 'BR.1898499644457061') }
  let!(:old_alias) { create(:contact_inbox, inbox: uno.inbox, contact: canonical, source_id: '5566996092506') }
  let!(:legacy_alias) { create(:contact_inbox, inbox: meta.inbox, contact: legacy, source_id: legacy.bsuid) }
  let!(:phone_alias) { create(:contact_inbox, inbox: meta.inbox, contact: legacy, source_id: '556696092506') }
  let!(:conversation) { create(:conversation, inbox: meta.inbox, account: account, contact: legacy, contact_inbox: legacy_alias) }
  let!(:message) { create(:message, account: account, inbox: meta.inbox, conversation: conversation, sender: legacy, message_type: :incoming, source_id: 'wamid.keep') }
  subject(:service) { described_class.new(link: link, pairs: [[legacy.id, canonical.id]]) }

  it 'previews without changing a contact, alias, conversation or message' do
    before = [canonical.reload.attributes, legacy.reload.attributes, conversation.reload.attributes, message.reload.attributes, legacy_alias.reload.attributes]
    preview = service.preview
    expect(preview[:blocked]).to be(false)
    expect(preview).to include(deletes: 0, message_moves: 0, media_changes: 0)
    expect(preview[:pairs].sole[:message_ids]).to include(message.id)
    expect([canonical.reload.attributes, legacy.reload.attributes, conversation.reload.attributes,
            message.reload.attributes, legacy_alias.reload.attributes]).to eq(before)
  end

  it 'reconciles relationships while retaining both contacts, conversation/message IDs, content and media' do
    attachment = message.attachments.build(account: account, file_type: :image)
    attachment.file.attach(io: StringIO.new(Rails.root.join('spec/assets/sample.png').binread), filename: 'keep.png', content_type: 'image/png')
    attachment.save!
    before = canonical.reload.attributes
    message_before = message.reload.attributes.except('sender_id')
    blob_id = attachment.file.blob.id
    blob_count = ActiveStorage::Blob.count

    preview = service.preview
    result = service.apply!(fingerprint: preview[:fingerprint])

    expect(result[:applied]).to be(true)
    expect(canonical.reload.attributes).to eq(before)
    expect(legacy.reload.id).to eq(legacy.id)
    expect(conversation.reload.contact_id).to eq(canonical.id)
    expect(message.reload.attributes.except('sender_id')).to eq(message_before)
    expect(message.sender_id).to eq(canonical.id)
    expect(legacy_alias.reload.contact_id).to eq(canonical.id)
    expect(legacy_alias.source_id).to eq('BR.1898499644457061')
    expect(phone_alias.reload.source_id).to eq('556696092506')
    expect(old_alias.reload.contact_id).to eq(canonical.id)
    expect(attachment.reload.file.blob.id).to eq(blob_id)
    expect(ActiveStorage::Blob.count).to eq(blob_count)
    expect { service.apply!(fingerprint: preview[:fingerprint]) }.to raise_error(ArgumentError, /blocked|changed/)
  end

  it 'refuses a preview whose IDs changed before the application' do
    preview = service.preview
    create(:message, account: account, inbox: meta.inbox, conversation: conversation, sender: legacy)
    expect { service.apply!(fingerprint: preview[:fingerprint]) }.to raise_error(ArgumentError, /changed/)
    expect(conversation.reload.contact_id).to eq(legacy.id)
  end

  it 'blocks contradictory phone evidence without applying anything' do
    phone_alias.update!(source_id: '5566996263708')
    preview = service.preview
    expect(preview[:blocked]).to be(true)
    expect { service.apply!(fingerprint: preview[:fingerprint]) }.to raise_error(ArgumentError, /blocked/)
    expect(legacy_alias.reload.contact_id).to eq(legacy.id)
  end

  it 'does not reconcile groups as direct-chat identities' do
    conversation.update!(group: true, group_source_id: '123456@g.us')
    expect(service.preview[:pairs].sole[:blockers]).to include('group_conversation')
  end

  it 'blocks scheduled messages referencing the legacy contact instead of silently invalidating them' do
    create(:scheduled_message, account: account, inbox: meta.inbox, conversation: conversation, contact: legacy)
    expect(service.preview[:pairs].sole[:blockers]).to include('dependent_reference:scheduled_messages.contact_id')
  end
end
