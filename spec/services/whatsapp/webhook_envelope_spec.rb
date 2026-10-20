require 'rails_helper'

RSpec.describe Whatsapp::WebhookEnvelope do
  it 'splits every entry/change without losing WABA, timestamp or URL scope' do
    params = { object: 'whatsapp_business_account', phone_number: '+5511999999999', entry: [
      { id: 'waba-a', time: 123, changes: [{ field: 'account_alerts', value: { status: 'RESTRICTED' } },
                                           { field: 'security', value: { status: 'ACTIVE' } }] },
      { id: 'waba-b', changes: [{ field: 'business_capability_update', value: { current_limit: 2000 } }] }
    ] }
    units = described_class.units(params)
    expect(units.size).to eq(3)
    expect(units.map { |item| item.dig(:entry, 0, :id) }).to eq(%w[waba-a waba-a waba-b])
    expect(units.map { |item| item[:phone_number] }.uniq).to eq(['+5511999999999'])
    expect(units.first.dig(:entry, 0, :time)).to eq(123)
  end

  it 'isolates messages and statuses, with contact evidence only for the matching sender' do
    params = { entry: [{ changes: [{ field: 'messages', value: {
      messages: [{ from: '111', id: 'first' }, { from: '222', id: 'second' }],
      contacts: [{ wa_id: '111' }, { wa_id: '222' }], statuses: [{ id: 'third', status: 'read' }]
    } }] }] }
    values = described_class.units(params).map { |item| item.dig(:entry, 0, :changes, 0, :value) }
    expect(values.size).to eq(3)
    expect(values.first[:contacts]).to eq([{ 'wa_id' => '111' }])
    expect(values.second[:contacts]).to eq([{ 'wa_id' => '222' }])
    expect(values.first[:statuses]).to be_nil
    expect(values.last[:messages]).to be_nil
  end

  it 'ignores malformed batch members instead of raising' do
    expect(described_class.units(entry: [nil, 'bad', { changes: ['bad', nil] }])).to eq([])
  end
end
