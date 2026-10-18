require 'rails_helper'

RSpec.describe Whatsapp::MessageIdentityCorrelationService do
  let(:account) { create(:account) }
  let(:suffix) { SecureRandom.random_number(10**7).to_s.rjust(7, '0') }
  let(:channels) do
    %w[whatsapp_cloud unoapi].index_with do |provider|
      number = provider == 'whatsapp_cloud' ? "+55658#{suffix}" : "+556598#{suffix}"
      create(:channel_whatsapp, account: account, provider: provider, phone_number: number,
                                sync_templates: false, validate_provider_config: false)
    end
  end
  let!(:identities) do
    channels.map do |provider, channel|
      WhatsappMessageIdentity.create!(account: account, inbox: channel.inbox, channel: channel, provider: provider,
                                      external_id: "#{provider}-public-id", provider_message_id: 'original-id',
                                      observations: { 'business_number' => channel.phone_number, 'direction' => 'incoming',
                                                      'message_type' => 'text', 'participants' => { 'from' => '5565987654321' } })
    end
  end

  %w[whatsapp_cloud unoapi].each do |provider|
    context "with the receipt on #{provider}" do
      let(:identity) { identities.find { |item| item.provider == provider } }
      let(:partner) { channels.except(provider).values.sole.inbox }
      let(:service) { described_class.new(identity: identity, partner_inbox: partner) }

      it 'matches an incoming receipt whose recipient is the same peer' do
        observations = identity.observations.deep_dup
        observations['participants']['recipient_id'] = '5565987654321'
        identity.update!(observations: observations)

        expect(service.perform[:status]).to eq('matched')
        expect(service.safe_for_unification?).to be(true)
      end

      it 'blocks an incoming receipt with the wrong recipient' do
        observations = identity.observations.deep_dup
        observations['participants']['recipient_id'] = '5511987654321'
        identity.update!(observations: observations)

        expect(service.perform[:status]).to eq('conflicting_observations')
        expect(service.safe_for_unification?).to be(false)
      end

      it 'blocks genuine contradictory direction and sender observations' do
        observations = identity.observations.merge(
          'conflicting_observations' => { 'direction' => %w[incoming outgoing],
                                          'participants.from' => ['5565987654321', identity.channel.phone_number] }
        )
        identity.update!(observations: observations)

        expect(service.perform[:status]).to eq('conflicting_observations')
        expect(service.safe_for_unification?).to be(false)
      end

      context 'with the production phone/hosted-LID receipt' do
        let!(:business_contact) do
          number = Whatsapp::InboxLinkPhoneService.normalize(identity.channel.phone_number)
          create(:contact, account: account, phone_number: "+#{number}", bsuid: '182222711709908@lid')
        end

        before do
          observations = identity.observations.deep_dup
          observations['statuses'] = { 'sent' => '1792229343' }
          observations['participants']['recipient_id'] = '5565987654321'
          observations['conflicting_observations'] = {
            'participants.recipient_id' => ['5565987654321', '182222711709908@hosted.lid']
          }
          identity.update!(observations: observations)
        end

        it 'accepts only the proven Uno business-device receipt without changing evidence' do
          snapshot = identity.attributes
          expected = provider == 'unoapi' ? 'matched' : 'conflicting_observations'

          expect(service.perform[:status]).to eq(expected)
          expect(identity.reload.attributes).to eq(snapshot)
        end

        it 'keeps an unrelated LID in review rather than guessing a phone' do
          business_contact.update!(phone_number: '+5511987654321')

          expect(service.perform[:status]).to eq('conflicting_observations')
        end

        it 'does not bypass conflicting directions when the receipt alias is proven' do
          identity.update!(observations: identity.observations.deep_merge('conflicting_observations' => { 'direction' => %w[incoming outgoing] }))

          expect(service.perform[:status]).to eq('conflicting_observations')
        end

        it 'does not trust an alias from another account' do
          business_contact.update!(account: create(:account))

          expect(service.perform[:status]).to eq('conflicting_observations')
        end

        it 'does not apply the device exception to a message without receipts' do
          identity.update!(observations: identity.observations.except('statuses'))

          expect(service.perform[:status]).to eq('conflicting_observations')
        end

        it 'blocks an ambiguous established LID instead of choosing the first contact' do
          other = create(:contact, account: account, phone_number: '+5511987654321')
          legacy_alias = create(:contact_inbox, inbox: identity.inbox, contact: other, source_id: '5511987654321')
          # Existing installations contain LID aliases predating today's validation.
          legacy_alias.update_column(:source_id, '182222711709908@hosted.lid')

          expect(service.perform[:status]).to eq('conflicting_observations')
        end
      end
    end
  end
end
