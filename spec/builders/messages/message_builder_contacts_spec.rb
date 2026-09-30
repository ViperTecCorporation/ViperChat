require 'rails_helper'

describe Messages::MessageBuilder do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:contacts) do
    [{ formatted_name: 'First', phone_number: '+15555550101' },
     { formatted_name: 'Second', email: 'second@example.com' }]
  end
  let(:params) { { content_attributes: { contacts: contacts } } }

  it 'persists multiple contacts in one message' do
    message = described_class.new(user, conversation, params).perform
    expect(message.reload.attachments.map(&:file_type)).to eq %w[contact contact]
    expect(message.attachments.last.meta['email']).to eq 'second@example.com'
  end

  it 'rejects the whole message when one contact has no address' do
    contacts.last.delete(:email)
    conversation
    expect do
      expect { described_class.new(user, conversation, params).perform }
        .to raise_error(ArgumentError, /Second/)
    end.not_to change(Message, :count)
  end

  it 'rejects a contact without a name' do
    contacts.first.delete(:formatted_name)
    expect { described_class.new(user, conversation, params).perform }
      .to raise_error(ArgumentError, /name and a phone number or email/)
  end
end
