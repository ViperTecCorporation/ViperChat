require 'rails_helper'

RSpec.describe WhatsappInboxLink do
  let(:account) { create(:account) }
  let(:uno) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+556696222471',
                             sync_templates: false, validate_provider_config: false).inbox
  end
  let(:meta) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '5566996222471',
                             sync_templates: false, validate_provider_config: false).inbox
  end
  let(:link) { described_class.new(account: account, primary_inbox: uno, secondary_inbox: meta, default_provider: 'whatsapp_cloud') }

  it 'defaults to disabled and does not expose a draft as active' do
    expect(described_class.for_inbox(nil)).to be_nil
    link.save!
    expect(link).not_to be_enabled
    expect(link.activated_at).to be_nil
    expect(described_class.for_inbox(uno)).to be_nil
  end

  it 'supports either primary and a default provider independent of the primary' do
    link.assign_attributes(primary_inbox: meta, secondary_inbox: uno, enabled: true, default_provider: 'unoapi')
    link.save!
    expect(link.activated_at).to be_present
    expect(described_class.for_inbox(uno)).to eq(link)
    expect(described_class.for_inbox(meta)).to eq(link)
    expect(link.inbox_for('unoapi')).to eq(uno)
    expect(link.inbox_for('whatsapp_cloud')).to eq(meta)
    expect(link.partner_for(uno)).to eq(meta)
    expect(link.partner_for(meta)).to eq(uno)
    expect(link.inbox_for('default')).to be_nil
    expect(link.partner_for(create(:inbox, account: account))).to be_nil
  end

  it 'preserves the cutoff on ordinary updates and disabling, but sets a fresh one on reactivation' do
    link.update!(enabled: true)
    cutoff = link.activated_at
    travel_to 1.hour.from_now do
      link.update!(default_provider: 'unoapi')
      expect(link.activated_at).to eq(cutoff)
      link.update!(enabled: false)
      expect(link.activated_at).to eq(cutoff)
      expect(described_class.for_inbox(meta)).to be_nil
      link.update!(enabled: true)
      expect(link.activated_at).to be > cutoff
    end
  end

  it 'rejects an overlapping enabled pair across the opposite index columns' do
    link.update!(enabled: true)
    other = described_class.new(account: account, primary_inbox: meta, secondary_inbox: uno, enabled: true, default_provider: 'unoapi')
    expect(other).not_to be_valid
    expect(other.errors.full_messages.join).to include('already belongs')
    expect { other.save! }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'rechecks overlap under the account lock after the initial validation' do
    other = described_class.new(account: account, primary_inbox: meta, secondary_inbox: uno, enabled: true, default_provider: 'unoapi')
    expect(other).to be_valid
    link.update!(enabled: true)
    expect { other.save!(validate: false) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'rejects cross-account, duplicate inboxes and unsupported providers' do
    link.account = create(:account)
    expect(link).not_to be_valid
    link.account = account
    link.secondary_inbox = uno
    expect(link).not_to be_valid
    link.secondary_inbox = create(:inbox, account: account)
    expect(link).not_to be_valid
    link.secondary_inbox = meta
    link.default_provider = 'default'
    expect(link).not_to be_valid
  end

  it 'compares a validated legacy BR mobile without changing either stored business number' do
    link.save!
    expect(uno.channel.reload.phone_number).to eq('+556696222471')
    expect(meta.channel.reload.phone_number).to eq('5566996222471')
  end

  it 'rejects genuinely different business numbers' do
    meta.channel.update_column(:phone_number, '5566991111111')
    expect(link).not_to be_valid
    expect(link.errors.full_messages.join).to include('phone numbers must match')
  end

  it 'rejects changing the primary on an active pair until it has first been disabled' do
    link.update!(enabled: true)
    link.assign_attributes(primary_inbox: meta, secondary_inbox: uno)
    expect(link).not_to be_valid
  end
end
