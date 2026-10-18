require 'rails_helper'

RSpec.describe Whatsapp::HistoryContactResolver do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:resolver) { described_class.new(inbox: channel.inbox, peer: '556587654321', message: {}) }

  it 'queries candidates after taking the same account/phone lock as live creation' do
    existing = nil
    allow(Whatsapp::ContactIdentityLock).to receive(:synchronize).and_wrap_original do |method, **args, &block|
      expect(args).to eq(account_id: account.id, phone: '556587654321')
      existing = create(:contact, account: account, phone_number: '+5565987654321', name: 'Antigo')
      method.call(**args, &block)
    end

    result = resolver.perform
    expect(result.contact_id).to eq(existing.id)
    expect(result.source_id).to eq('556587654321')
    expect(account.contacts.pluck(:id)).to eq([existing.id])
  end

  it 'shares a historical contact with a normal builder in another WhatsApp inbox' do
    historical = resolver.perform
    other = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                      sync_templates: false, validate_provider_config: false)
    live = ContactInboxWithContactBuilder.new(inbox: other.inbox, source_id: '5565987654321',
                                              contact_attributes: { phone_number: '+5565987654321', name: 'Live' }).perform

    expect(live.contact_id).to eq(historical.contact_id)
    expect(account.contacts.count).to eq(1)
    expect(historical.reload.source_id).to eq('556587654321')
    expect(live.source_id).to eq('5565987654321')
  end
end
