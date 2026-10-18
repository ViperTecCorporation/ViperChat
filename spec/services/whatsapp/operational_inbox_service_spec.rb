require 'rails_helper'

RSpec.describe Whatsapp::OperationalInboxService do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:meta_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+556696222471',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:uno_channel) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5566996222471',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:contact) { create(:contact, account: account, phone_number: '+5566996269251', name: 'Existing recipient') }

  %w[whatsapp_cloud unoapi].each do |principal|
    context "with #{principal} as principal" do
      let(:primary) { principal == 'whatsapp_cloud' ? meta_channel.inbox : uno_channel.inbox }
      let(:secondary) { principal == 'whatsapp_cloud' ? uno_channel.inbox : meta_channel.inbox }
      let!(:link) do
        WhatsappInboxLink.create!(account: account, primary_inbox: primary, secondary_inbox: secondary,
                                  default_provider: 'whatsapp_cloud', enabled: true)
      end
      let!(:primary_alias) do
        create(:contact_inbox, contact: contact, inbox: primary,
                               source_id: principal == 'whatsapp_cloud' ? '556696269251' : '5566996269251')
      end
      let!(:secondary_alias) do
        create(:contact_inbox, contact: contact, inbox: secondary,
                               source_id: principal == 'whatsapp_cloud' ? '5566996269251' : '556696269251')
      end

      before do
        Current.account = account
        Current.user = admin
        Current.account_user = account.account_users.find_by!(user: admin)
      end

      after { Current.reset }

      it 'maps either physical inbox to the principal without changing aliases' do
        expect(described_class.canonical(inbox: primary, contact: contact)).to eq(primary)
        expect(described_class.canonical(inbox: secondary, contact: contact, source_id: secondary_alias.source_id)).to eq(primary)
        expect(primary_alias.reload.source_id).not_to eq(secondary_alias.reload.source_id)
      end

      it 'reuses the principal alias rather than copying a stale secondary source' do
        expect do
          result = described_class.contact_inbox(contact: contact, inbox: secondary, source_id: secondary_alias.source_id)
          expect(result.id).to eq(primary_alias.id)
          expect(result.source_id).to eq(primary_alias.source_id)
        end.not_to change(ContactInbox, :count)
      end

      it 'does not move existing physical conversations while resolving the principal' do
        legacy = create(:conversation, account: account, inbox: secondary, contact: contact, contact_inbox: secondary_alias)
        snapshot = legacy.reload.attributes

        described_class.canonical(inbox: secondary, contact: contact, conversation: legacy)
        described_class.contact_inbox(contact: contact, inbox: secondary, source_id: secondary_alias.source_id)

        expect(legacy.reload.attributes).to eq(snapshot)
      end

      it 'keeps group conversations on their physical inbox' do
        group = create(:conversation, account: account, inbox: secondary, contact: contact, contact_inbox: secondary_alias,
                                      group: true, group_source_id: '120363000000001@g.us')

        expect(described_class.canonical(inbox: secondary, conversation: group)).to eq(secondary)
        expect(described_class.canonical(inbox: secondary, source_id: 'unproven@g.us')).to eq(primary)
      end

      it 'accepts a stored group association but not a forged group source for a direct contact' do
        group_contact = create(:contact, account: account, phone_number: nil, email: '120363000000001@g.us')
        create(:contact_inbox, contact: group_contact, inbox: secondary, source_id: group_contact.email)

        expect(described_class.canonical(inbox: secondary, source_id: group_contact.email)).to eq(secondary)
        expect(described_class.canonical(inbox: secondary, contact: contact, source_id: group_contact.email)).to eq(primary)
      end

      it 'allows a primary-only agent to authorize a secondary selection' do
        create(:inbox_member, inbox: primary, user: agent)

        effective = described_class.canonical(inbox: secondary)
        expect { described_class.authorize!(inbox: effective, user: agent) }.not_to raise_error
      end

      it 'does not let a secondary-only agent bypass the principal' do
        create(:inbox_member, inbox: secondary, user: agent)

        effective = described_class.canonical(inbox: secondary)
        expect { described_class.authorize!(inbox: effective, user: agent) }.to raise_error do |error|
          expect(error.class.name).to eq('Pundit::NotAuthorizedError')
        end
      end

      it 'rejects a foreign-account administrator' do
        outsider = create(:user, account: create(:account), role: :administrator)

        expect { described_class.authorize!(inbox: secondary, user: outsider) }.to raise_error do |error|
          expect(error.class.name).to eq('Pundit::NotAuthorizedError')
        end
      end

      it 'exposes both transport templates to an authorized principal user' do
        metadata = described_class.metadata(inbox: primary).deep_stringify_keys

        expect(metadata).to include('link_id' => link.id, 'primary_inbox_id' => primary.id,
                                    'primary_inbox_name' => primary.name, 'secondary_inbox_id' => secondary.id,
                                    'default_provider' => 'whatsapp_cloud')
        expect(metadata.fetch('transports')).to contain_exactly(
          include('provider' => 'whatsapp_cloud', 'label' => 'Meta', 'inbox_id' => meta_channel.inbox.id,
                  'channel_type' => 'Channel::Whatsapp', 'message_templates' => meta_channel.message_templates),
          include('provider' => 'unoapi', 'label' => 'ViperConnect', 'inbox_id' => uno_channel.inbox.id,
                  'channel_type' => 'Channel::Whatsapp', 'message_templates' => uno_channel.message_templates)
        )
        expect(described_class.metadata(inbox: secondary).deep_stringify_keys).to eq(metadata)
      end

      it 'hides metadata from a secondary-only agent' do
        create(:inbox_member, inbox: secondary, user: agent)
        Current.user = agent
        Current.account_user = account.account_users.find_by!(user: agent)

        expect(described_class.metadata(inbox: primary)).to be_nil
        expect(described_class.metadata(inbox: secondary)).to be_nil
      end

      it 'leaves a disabled pair physical and omits metadata' do
        link.update!(enabled: false)

        expect(described_class.canonical(inbox: secondary, contact: contact)).to eq(secondary)
        expect(described_class.metadata(inbox: primary)).to be_nil
      end

      it 'does not steal a principal identity owned by another contact' do
        primary_alias.destroy!
        owner = create(:contact, account: account, phone_number: '+5511987654321')
        occupied = create(:contact_inbox, contact: owner, inbox: primary, source_id: contact.phone_number.delete_prefix('+'))

        expect do
          described_class.contact_inbox(contact: contact, inbox: secondary, source_id: occupied.source_id)
        end.to raise_error(ArgumentError, /another contact/)
        expect(occupied.reload.contact_id).to eq(owner.id)
        expect(secondary_alias.reload.contact_id).to eq(contact.id)
        expect(contact.contact_inboxes.where(inbox: primary)).to be_empty
      end

      it 'rejects a foreign-account contact without creating an alias' do
        foreign_contact = create(:contact, account: create(:account))

        expect do
          described_class.contact_inbox(contact: foreign_contact, inbox: primary)
        end.to raise_error(ArgumentError, /same account/)
        expect(foreign_contact.contact_inboxes).to be_empty
      end
    end
  end

  it 'preserves an unlinked inbox' do
    expect(described_class.canonical(inbox: uno_channel.inbox)).to eq(uno_channel.inbox)
    expect(described_class.metadata(inbox: uno_channel.inbox)).to be_nil
  end
end
