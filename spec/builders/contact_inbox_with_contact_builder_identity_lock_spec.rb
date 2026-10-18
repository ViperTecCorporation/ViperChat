require 'rails_helper'

RSpec.describe ContactInboxWithContactBuilder do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:builder) do
    described_class.new(inbox: inbox, source_id: '556587654321',
                        contact_attributes: { phone_number: '+556587654321', name: 'Contato' })
  end

  it 'reuses the contact created before acquiring the shared lock rather than creating an 8-digit duplicate' do
    existing = nil
    allow(Whatsapp::ContactIdentityLock).to receive(:synchronize).and_wrap_original do |method, **args, &block|
      existing = create(:contact, account: account, phone_number: '+5565987654321', name: 'Antigo')
      method.call(**args, &block)
    end

    result = builder.perform
    expect(result.contact_id).to eq(existing.id)
    expect(account.contacts.pluck(:id)).to eq([existing.id])
    expect(existing.reload.phone_number).to eq('+5565987654321')
    expect(result.source_id).to eq('556587654321')
  end

  it 'reuses an old 8-digit contact for a 9-digit phone without rewriting the old record' do
    existing = create(:contact, account: account, phone_number: '+5565987654321', name: 'Antigo')
    existing.update_column(:phone_number, '+556587654321') # rubocop:disable Rails/SkipsModelValidations
    result = described_class.new(inbox: inbox, source_id: '5565987654321',
                                 contact_attributes: { phone_number: '+5565987654321', name: 'Novo nome' }).perform

    expect(result.contact_id).to eq(existing.id)
    expect(existing.reload.phone_number).to eq('+556587654321')
    expect(account.contacts.count).to eq(1)
  end

  it 'leaves non-WhatsApp builders outside the shared lock' do
    widget = create(:inbox, account: account)
    expect(Whatsapp::ContactIdentityLock).not_to receive(:synchronize)
    result = described_class.new(inbox: widget, source_id: 'widget-contact',
                                 contact_attributes: { name: 'Widget', phone_number: '+5565987654321' }).perform
    expect(result.inbox_id).to eq(widget.id)
  end

  it 'does not reuse a matching phone from another account' do
    foreign = create(:contact, phone_number: '+5565987654321')
    result = described_class.new(inbox: inbox, source_id: '5565987654321',
                                 contact_attributes: { phone_number: '+5565987654321', name: 'Local' }).perform
    expect(result.contact_id).not_to eq(foreign.id)
    expect(result.contact.account_id).to eq(account.id)
  end
end
