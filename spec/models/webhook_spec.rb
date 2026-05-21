require 'rails_helper'

RSpec.describe Webhook do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:account_id) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
  end

  describe 'secret token' do
    let!(:account) { create(:account) }

    it 'auto-generates a secret on create' do
      webhook = create(:webhook, account: account)
      expect(webhook.secret).to be_present
    end

    it 'does not regenerate the secret on update' do
      webhook = create(:webhook, account: account)
      original_secret = webhook.secret
      webhook.update!(url: "#{webhook.url}?updated=1")
      expect(webhook.reload.secret).to eq(original_secret)
    end
  end

  describe 'webhook_type callbacks' do
    let!(:account) { create(:account) }
    let!(:inbox) { create(:inbox, account: account) }

    it 'sets webhook_type to inbox_type if inbox_id is present' do
      webhook = create(:webhook, account: account, inbox_id: inbox.id)
      expect(webhook.webhook_type).to eq('inbox_type')
    end

    it 'sets webhook_type to account_type if inbox_id is nil' do
      webhook = create(:webhook, account: account, inbox_id: nil)
      expect(webhook.webhook_type).to eq('account_type')
    end

    it 'clears inbox_id and sets webhook_type to account_type if inbox_id is cleared' do
      webhook = create(:webhook, account: account, inbox_id: inbox.id)
      expect(webhook.webhook_type).to eq('inbox_type')
      
      webhook.update!(inbox_id: nil)
      expect(webhook.webhook_type).to eq('account_type')
      expect(webhook.inbox_id).to be_nil
    end
  end
end
