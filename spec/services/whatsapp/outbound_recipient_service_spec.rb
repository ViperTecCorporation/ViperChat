require 'rails_helper'

RSpec.describe Whatsapp::OutboundRecipientService do
  subject(:recipient) { described_class.new(conversation: conversation, inbox: channel.inbox).perform }

  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:conversation) { create(:conversation, inbox: channel.inbox) }

  before do
    conversation.contact_inbox.update!(source_id: 'BR.1316081087211411')
    conversation.contact.update!(phone_number: nil, bsuid: '30984414191647@lid')
  end

  it 'preserves the complete Meta BSUID when no phone has been disclosed in that inbox' do
    expect(recipient).to eq('BR.1316081087211411')
  end

  it 'does not prefer a canonical ninth-digit phone to an existing Meta-only BSUID' do
    conversation.contact.update!(phone_number: '+5565996598456')
    expect(recipient).to eq('BR.1316081087211411')
  end

  it 'does not reuse the phone of another inbox as a Meta phone alias' do
    other = create(:channel_whatsapp, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
    create(:contact_inbox, inbox: other.inbox, contact: conversation.contact, source_id: '5565996598456')
    expect(recipient).to eq('BR.1316081087211411')
  end

  it 'uses the canonical contact phone only when the selected inbox has no usable Meta identity' do
    conversation.contact_inbox.update!(source_id: '30984414191647@lid')
    conversation.contact.update!(phone_number: '+5565996598456')
    expect(recipient).to eq('5565996598456')
  end

  it 'does not invent a Meta phone by stripping a LID' do
    conversation.contact_inbox.update!(source_id: '30984414191647@lid')
    expect { recipient }.to raise_error(ArgumentError, /Recipient identity pending/)
  end

  it 'does not borrow a BSUID from a different Meta inbox when the selected inbox has only a LID' do
    conversation.contact_inbox.update!(source_id: '30984414191647@lid')
    other = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    create(:contact_inbox, inbox: other.inbox, contact: conversation.contact, source_id: 'BR.1316081087211411')
    expect { recipient }.to raise_error(ArgumentError, /Recipient identity pending/)
  end

  it 'keeps group addressing independent of individual aliases' do
    conversation.update!(group: true, group_source_id: '120363040468224422@g.us')
    expect(recipient).to eq('120363040468224422@g.us')
  end

  it 'retains Uno LID routing without applying Meta recipient rules' do
    channel.update!(provider: 'unoapi', provider_config: { 'api_key' => 'synthetic', 'url' => 'https://uno.invalid' })
    conversation.contact_inbox.update!(source_id: '30984414191647@lid')
    expect(recipient).to eq('30984414191647@lid')
  end
end
