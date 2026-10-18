require 'rails_helper'

RSpec.describe Contact, '#historical_import' do
  let(:contact) { build(:contact, account: create(:account), historical_import: true) }

  it 'persists without contact-created automation or IP lookup' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    expect(contact).not_to receive(:ip_lookup)

    contact.save!

    expect(contact.id).to be_present
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with('contact.created', anything, anything)
    expect(described_class.find(contact.id).historical_import).to be_nil
  end

  it 'retains account scoping and uniqueness validation' do
    existing = create(:contact, account: contact.account, identifier: 'historical-contact')
    contact.identifier = existing.identifier

    expect(contact).not_to be_valid
    expect(contact.errors[:identifier]).to be_present

    contact.account = create(:account)
    expect(contact).to be_valid
  end

  it 'dispatches updates normally after reload' do
    contact.save!
    contact.reload
    allow(Rails.configuration.dispatcher).to receive(:dispatch)

    contact.update!(name: 'Updated after import')

    expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
      'contact.updated', kind_of(Time), contact: contact, changed_attributes: anything
    )
  end

  it 'dispatches contact-created normally without the context' do
    contact.historical_import = nil
    allow(Rails.configuration.dispatcher).to receive(:dispatch)

    contact.save!

    expect(Rails.configuration.dispatcher).to have_received(:dispatch).with('contact.created', kind_of(Time), contact: contact)
  end
end
