require 'rails_helper'

describe ContactInboxWithContactBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, email: 'xyc@example.com', phone_number: '+23423424123', account: account, identifier: '123') }
  let(:existing_contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }

  describe '#perform' do
    it 'doesnot create contact if it already exist with source id' do
      contact_inbox = described_class.new(
        source_id: existing_contact_inbox.source_id,
        inbox: inbox,
        contact_attributes: {
          name: 'Contact',
          phone_number: '+1234567890',
          email: 'testemail@example.com'
        }
      ).perform

      expect(contact_inbox.contact.id).to be(contact.id)
    end

    it 'creates contact if contact doesnot exist with source id' do
      contact_inbox = described_class.new(
        source_id: '123456',
        inbox: inbox,
        contact_attributes: {
          name: 'Contact',
          phone_number: '+1234567890',
          email: 'testemail@example.com',
          custom_attributes: { test: 'test' }
        }
      ).perform

      expect(contact_inbox.contact.id).not_to eq(contact.id)
      expect(contact_inbox.contact.name).to eq('Contact')
      expect(contact_inbox.contact.custom_attributes).to eq({ 'test' => 'test' })
      expect(contact_inbox.inbox_id).to eq(inbox.id)
    end

    it 'doesnot create contact if it already exist with identifier' do
      contact_inbox = described_class.new(
        source_id: '123456',
        inbox: inbox,
        contact_attributes: {
          name: 'Contact',
          identifier: contact.identifier,
          phone_number: contact.phone_number,
          email: 'testemail@example.com'
        }
      ).perform

      expect(contact_inbox.contact.id).to be(contact.id)
    end

    it 'doesnot create contact if it already exist with email' do
      contact_inbox = described_class.new(
        source_id: '123456',
        inbox: inbox,
        contact_attributes: {
          name: 'Contact',
          phone_number: '+1234567890',
          email: contact.email
        }
      ).perform

      expect(contact_inbox.contact.id).to be(contact.id)
    end

    it 'doesnot create contact when an uppercase email is passed for an already existing contact email' do
      contact_inbox = described_class.new(
        source_id: '123456',
        inbox: inbox,
        contact_attributes: {
          name: 'Contact',
          phone_number: '+1234567890',
          email: contact.email.upcase
        }
      ).perform

      expect(contact_inbox.contact.id).to be(contact.id)
    end

    it 'doesnot create contact if it already exist with phone number' do
      contact_inbox = described_class.new(
        source_id: '123456',
        inbox: inbox,
        contact_attributes: {
          name: 'Contact',
          phone_number: contact.phone_number,
          email: 'testemail@example.com'
        }
      ).perform

      expect(contact_inbox.contact.id).to be(contact.id)
    end

    it 'reuses and enriches contact if it already exists with bsuid' do
      existing_contact = create(:contact, account: account, bsuid: '123456789012345@lid', phone_number: nil)

      contact_inbox = described_class.new(
        source_id: '5566999999999',
        inbox: inbox,
        contact_attributes: {
          name: 'Maria',
          bsuid: '123456789012345@lid',
          whatsapp_username: '@maria.vendas',
          phone_number: '+5566999999999'
        }
      ).perform

      expect(contact_inbox.contact.id).to eq(existing_contact.id)
      expect(contact_inbox.contact.reload.phone_number).to eq('+5566999999999')
      expect(contact_inbox.contact.whatsapp_username).to eq('@maria.vendas')
    end

    it 'adds bsuid to an existing phone contact' do
      contact_inbox = described_class.new(
        source_id: '556699999999',
        inbox: inbox,
        contact_attributes: {
          name: 'Maria',
          bsuid: '123456789012345@lid',
          phone_number: contact.phone_number
        }
      ).perform

      expect(contact_inbox.contact.id).to eq(contact.id)
      expect(contact.reload.bsuid).to eq('123456789012345@lid')
    end

    it 'does not enqueue avatar import when avatar url is blank' do
      expect do
        described_class.new(
          source_id: '556699999998',
          inbox: inbox,
          contact_attributes: {
            name: 'Maria',
            phone_number: '+1556699999998',
            avatar_url: ''
          }
        ).perform
      end.not_to have_enqueued_job(Avatar::AvatarFromUrlJob)
    end

    it 'does not enqueue avatar import when the avatar url hash is unchanged' do
      avatar_url = 'https://cdn.example.com/profile/maria.jpg'
      contact.update!(additional_attributes: { 'avatar_url_hash' => Digest::SHA256.hexdigest(avatar_url) })

      expect do
        described_class.new(
          source_id: existing_contact_inbox.source_id,
          inbox: inbox,
          contact_attributes: {
            name: 'Maria',
            avatar_url: avatar_url
          }
        ).perform
      end.not_to have_enqueued_job(Avatar::AvatarFromUrlJob)
    end

    it 'does not enqueue avatar import when only signed url parameters change' do
      original_avatar_url = 'https://cdn.example.com/profile/maria.jpg?X-Amz-Signature=old&X-Amz-Date=20260615T120000Z'
      next_avatar_url = 'https://cdn.example.com/profile/maria.jpg?X-Amz-Signature=new&X-Amz-Date=20260615T130000Z'
      contact.update!(
        additional_attributes: {
          'avatar_url_hash' => Avatar::AvatarFromUrlJob.generate_url_hash(original_avatar_url)
        }
      )

      expect do
        described_class.new(
          source_id: existing_contact_inbox.source_id,
          inbox: inbox,
          contact_attributes: {
            name: 'Maria',
            avatar_url: next_avatar_url
          }
        ).perform
      end.not_to have_enqueued_job(Avatar::AvatarFromUrlJob)
    end

    it 'does not enqueue duplicate avatar imports while the same avatar url is already queued' do
      avatar_url = 'https://cdn.example.com/profile/maria.jpg'

      expect do
        2.times do
          described_class.new(
            source_id: existing_contact_inbox.source_id,
            inbox: inbox,
            contact_attributes: {
              name: 'Maria',
              avatar_url: avatar_url
            }
          ).perform
        end
      end.to have_enqueued_job(Avatar::AvatarFromUrlJob).once

      expect(contact.reload.additional_attributes['avatar_url_enqueued_hash']).to eq(Digest::SHA256.hexdigest(avatar_url))
    end

    it 'enqueues avatar import when the avatar metadata changes for the same url' do
      avatar_url = 'https://cdn.example.com/profile/maria.jpg'
      original_metadata = { etag: 'old-etag', content_length: 1234 }
      next_metadata = { etag: 'new-etag', content_length: 4321 }
      contact.update!(
        additional_attributes: {
          'avatar_url_hash' => Avatar::AvatarFromUrlJob.generate_url_hash(avatar_url, original_metadata)
        }
      )

      expect do
        described_class.new(
          source_id: existing_contact_inbox.source_id,
          inbox: inbox,
          contact_attributes: {
            name: 'Maria',
            avatar_url: avatar_url,
            avatar_metadata: next_metadata
          }
        ).perform
      end.to have_enqueued_job(Avatar::AvatarFromUrlJob).with(
        contact,
        avatar_url,
        { 'content_length' => '4321', 'etag' => 'new-etag' }
      )
    end

    it 'clears invalid legacy email before enriching an existing contact' do
      contact.update_columns(email: '123456789012345') # rubocop:disable Rails/SkipsModelValidations

      contact_inbox = described_class.new(
        source_id: '556699999999',
        inbox: inbox,
        contact_attributes: {
          name: 'Maria',
          bsuid: '123456789012345@lid',
          phone_number: contact.phone_number
        }
      ).perform

      expect(contact_inbox.contact.id).to eq(contact.id)
      expect(contact.reload.email).to be_nil
      expect(contact.bsuid).to eq('123456789012345@lid')
    end

    it 'reuses contact if it exists with the same source_id in a Facebook inbox when creating for Instagram inbox' do
      instagram_source_id = '123456789'

      # Create a Facebook page inbox with a contact using the same source_id
      facebook_inbox = create(:inbox, channel_type: 'Channel::FacebookPage', account: account)
      facebook_contact = create(:contact, account: account)
      facebook_contact_inbox = create(:contact_inbox, contact: facebook_contact, inbox: facebook_inbox, source_id: instagram_source_id)

      # Create an Instagram inbox
      instagram_inbox = create(:inbox, channel_type: 'Channel::Instagram', account: account)

      # Try to create a contact inbox with same source_id for Instagram
      contact_inbox = described_class.new(
        source_id: instagram_source_id,
        inbox: instagram_inbox,
        contact_attributes: {
          name: 'Instagram User',
          email: 'instagram_user@example.com'
        }
      ).perform

      # Should reuse the existing contact from Facebook
      expect(contact_inbox.contact.id).to eq(facebook_contact.id)
      # Make sure the contact inbox is not the same as the Facebook contact inbox
      expect(contact_inbox.id).not_to eq(facebook_contact_inbox.id)
      expect(contact_inbox.inbox_id).to eq(instagram_inbox.id)
    end
  end
end
