require 'rails_helper'

describe Whatsapp::Unoapi::LidIdentity do
  describe '.canonicalize' do
    it 'accepts canonical and device-suffixed LIDs' do
      expect(described_class.canonicalize('20173562093816@lid')).to eq('20173562093816@lid')
      expect(described_class.canonicalize('20173562093816:70@lid')).to eq('20173562093816@lid')
    end

    it 'rejects phone numbers and malformed or fabricated identifiers' do
      expect(described_class.canonicalize('5511912345678')).to be_nil
      expect(described_class.canonicalize('abc@lid')).to be_nil
      expect(described_class.canonicalize('20173562093816@s.whatsapp.net')).to be_nil
    end
  end
end
