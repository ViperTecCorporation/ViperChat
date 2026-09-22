require 'rails_helper'

RSpec.describe Whatsapp::Unoapi::IncomingGroupMentionsService do
  let(:account) { create(:account) }

  it 'resolves bare LID and phone mentions within the account' do
    create(:contact, account: account, name: 'Patricia', bsuid: '212721190613051@lid', phone_number: '+5566996933600')
    content = 'Oi @212721190613051, @212721190613051@lid e @5566996933600!'
    expect(described_class.new(account: account, content: content).perform).to eq('Oi @Patricia, @Patricia e @Patricia!')
  end

  it 'resolves a namespaced BSUID' do
    create(:contact, account: account, name: 'Maria', bsuid: 'BR.4462342527311286')
    expect(described_class.new(account: account, content: '@BR.4462342527311286').perform).to eq('@Maria')
  end

  it 'does not resolve contacts from another account or replace group IDs and email addresses' do
    create(:contact, name: 'Other account', bsuid: '212721190613051@lid')
    content = '@212721190613051 @120363421432834890@g.us test@123456.com'
    expect(described_class.new(account: account, content: content).perform).to eq(content)
  end

  it 'leaves ambiguous identifiers unchanged' do
    create(:contact, account: account, name: 'One', bsuid: '212721190613051@lid')
    create(:contact, account: account, name: 'Two', bsuid: '212721190613051')
    expect(described_class.new(account: account, content: '@212721190613051').perform).to eq('@212721190613051')
  end

  it 'escapes formatting in contact names' do
    create(:contact, account: account, name: '[Patricia](https://example.com)', bsuid: '212721190613051@lid')
    expect(described_class.new(account: account, content: '@212721190613051').perform)
      .to eq('@\\[Patricia\\]\\(https://example.com\\)')
  end
end
