require 'rails_helper'

RSpec.describe Whatsapp::ContactIdentityLock do
  let(:competitor) { ActiveRecord::Base.connection_pool.checkout }

  after { ActiveRecord::Base.connection_pool.checkin(competitor) }

  it 'contends across connections for the same account and Brazilian 8/9 comparison phone' do
    described_class.synchronize(account_id: 123, phone: '+556587654321') do
      competitor.transaction do
        key = competitor.quote('whatsapp-contact:123:5565987654321')
        expect(competitor.select_value("SELECT pg_try_advisory_xact_lock(hashtextextended(#{key}, 0))")).to be(false)
      end
    end
  end

  it 'does not lock another account or another phone' do
    described_class.synchronize(account_id: 123, phone: '+5565987654321') do
      competitor.transaction do
        %w[whatsapp-contact:124:5565987654321 whatsapp-contact:123:5565991234567].each do |value|
          key = competitor.quote(value)
          expect(competitor.select_value("SELECT pg_try_advisory_xact_lock(hashtextextended(#{key}, 0))")).to be(true)
        end
      end
    end
  end

  it 'does not invent a phone lock for BSUID, LID, groups or missing identity' do
    expect(ActiveRecord::Base.connection).not_to receive(:execute)
    [nil, 'BR.1765946091352996', '34050567848070@lid', '120363123@g.us'].each do |phone|
      expect(described_class.synchronize(account_id: 123, phone: phone) { :unchanged }).to eq(:unchanged)
    end
  end

  it 'returns the critical section result and exposes both comparison variants without changing stored phones' do
    expect(described_class.synchronize(account_id: 123, phone: '+5565987654321') { :result }).to eq(:result)
    expect(described_class.phone_variants('+556587654321')).to contain_exactly('5565987654321', '556587654321')
    expect(described_class.phone_variants('+5565987654321')).to contain_exactly('5565987654321', '556587654321')
  end
end
