require 'rails_helper'

RSpec.describe Whatsapp::UnifiedMessageMutationService do
  let(:account) { create(:account) }
  let!(:record) do
    parsed = Whatsapp::MetaMessageIdAdapter.parse(original_meta_id)
    WhatsappUnifiedMessage.create!(whatsapp_inbox_link: link, message: stored, original_id: parsed.fetch('provider_message_id'),
                                   participant_key: '5581981829525', direction: direction, message_kind: 'text', state: 'ready')
  end
  let(:event) do
    target = provider == 'unoapi' ? stored.source_id : original_meta_id
    event = { id: provider == 'unoapi' ? 'uno-edit-public-id' : event_meta_id, timestamp: Time.current.to_i.to_s }
    event[:provider_message_id] = '3EB09CFDFE4FAA96F1977B' if provider == 'unoapi'
    if direction == 'outgoing'
      event[:from] = channel.phone_number.delete_prefix('+')
      event[:to] = '5581981829525'
      event[:to_user_id] = 'BR.1472452464119038' if provider == 'whatsapp_cloud'
    else
      event[:from] = '5581981829525'
    end
    if operation == 'reaction'
      event[:type] = 'reaction'
      event[:reaction] = { message_id: target, emoji: '👍' }
    elsif operation == 'revoke'
      event[:type] = 'revoke'
      event[:revoke] = { original_message_id: target }
    elsif provider == 'unoapi'
      event.merge!(type: 'text', message_type: 'message_edit', provider_message_id: '3EB09CFDFE4FAA96F1977B',
                   context: { id: target }, text: { body: 'Texto editado sintético' })
    else
      event[:type] = 'edit'
      event[:edit] = { original_message_id: target, message: { type: 'text', text: { body: 'Texto editado sintético' } } }
    end
    event
  end
  let(:value) do
    { (direction == 'outgoing' ? :message_echoes : :messages) => [event],
      :contacts => [{ wa_id: '558188985300', profile: { name: 'Dispositivo comercial, não importar' } }] }.with_indifferent_access
  end
  let(:uno) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5581988985300',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:meta) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+558188985300',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:primary) { uno.inbox }
  let!(:link) do
    WhatsappInboxLink.create!(account: account, primary_inbox: primary, secondary_inbox: primary == uno.inbox ? meta.inbox : uno.inbox,
                              default_provider: 'unoapi', enabled: true)
  end
  let(:provider) { 'whatsapp_cloud' }
  let(:direction) { 'outgoing' }
  let(:operation) { 'edit' }
  let!(:contact) { create(:contact, account: account, phone_number: '+5581981829525', name: 'Contato sintético preservado') }
  let!(:conversation) { create(:conversation, account: account, inbox: primary, contact: contact) }
  let!(:stored) do
    create(:message, account: account, inbox: primary, conversation: conversation, message_type: direction,
                     source_id: 'uno-original-public-id', content: 'Texto original', content_attributes: { 'existing' => 'keep' })
  end

  def original_meta_id
    if direction == 'outgoing'
      'wamid.HBgTQlIuMTQ3MjQ1MjQ2NDExOTAzOBUUABEYFjNFQjBERjZCMTEzQ0VDNjg2MDRERDQA'
    elsif operation == 'revoke'
      'wamid.HBgMNTU4MTgxODI5NTI1FQIAEhgUM0FDODVDMzg5NDk5NkU3M0UxOUMA'
    else
      'wamid.HBgMNTU4MTgxODI5NTI1FQIAEhgUM0FEOEE5OUMzMzM2RTYzQkEyQTQA'
    end
  end

  def event_meta_id
    if operation == 'revoke'
      return 'wamid.HBgTQlIuMTQ3MjQ1MjQ2NDExOTAzOBUUABEYFjNFQjAyRkQ2REYxODE1NjVFMEYyNjQA' if direction == 'outgoing'

      return 'wamid.HBgMNTU4MTgxODI5NTI1FQIAEhgUM0FFQkJCM0M3ODY2MTI5QTI0OUEA'
    end
    if direction == 'outgoing'
      'wamid.HBgTQlIuMTQ3MjQ1MjQ2NDExOTAzOBUUABEYFjNFQjA5Q0ZERkU0RkFBOTZGMTk3N0IA'
    else
      'wamid.HBgMNTU4MTgxODI5NTI1FQIAEhgUM0E0RUQxQ0FCRDRCRTI1NkU1MEMA'
    end
  end
  before do
    create(:contact_inbox, inbox: meta.inbox, contact: contact, source_id: 'BR.1472452464119038')
    identity = WhatsappMessageIdentity.create!(account: account, inbox: uno.inbox, channel: uno, provider: 'unoapi',
                                               external_id: stored.source_id, provider_message_id: record.original_id,
                                               observations: { 'business_number' => uno.phone_number, 'direction' => direction,
                                                               'message_type' => 'text' })
    record.aliases.create!(whatsapp_message_identity: identity)
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  def inventory
    [Contact.order(:id).pluck(:id, :phone_number, :bsuid, :name), Conversation.order(:id).pluck(:id, :inbox_id, :contact_id, :status),
     Message.order(:id).pluck(:id, :source_id, :inbox_id, :conversation_id, :created_at), Attachment.order(:id).pluck(:id),
     ActiveStorage::Attachment.order(:id).pluck(:id, :blob_id), ActiveStorage::Blob.order(:id).pluck(:id, :key, :checksum, :byte_size)]
  end

  def channel
    provider == 'unoapi' ? uno : meta
  end

  def ingest(payload = value)
    echo = payload[:message_echoes].present?
    params = { entry: [{ changes: [{ field: echo ? 'smb_message_echoes' : 'messages', value: payload }] }] }
    service = provider == 'unoapi' ? Whatsapp::IncomingMessageUnoapiService : Whatsapp::IncomingMessageWhatsappCloudService
    service.new(inbox: channel.inbox, params: params.with_indifferent_access, outgoing_echo: echo).perform
  end

  %w[uno meta].product(%w[unoapi whatsapp_cloud], %w[incoming outgoing], %w[edit revoke reaction]).each do |principal, transport, flow, mutation|
    context "with #{mutation} via #{transport}, #{flow}, primary #{principal}" do
      let(:primary) { principal == 'uno' ? uno.inbox : meta.inbox }
      let(:provider) { transport }
      let(:direction) { flow }
      let(:operation) { mutation }

      it 'updates only the proven bubble and keeps IDs, conversations, contacts and media on retries' do
        stored.attachments.create!(account: account, file_type: :image,
                                   file: { io: File.open(Rails.root.join('spec/assets/avatar.png')), filename: 'preservado.png' })
        before_inventory = inventory
        2.times { ingest }
        expect(inventory).to eq(before_inventory)
        expect(stored.reload.content_attributes).to include('existing' => 'keep')
        if mutation == 'edit'
          expect(stored.content).to eq('Texto editado sintético')
          expect(stored.content_attributes).to include('edited' => true, 'previous_content' => 'Texto original')
        elsif mutation == 'revoke'
          expect(stored.content_attributes).to include('deleted' => true)
        else
          expect(stored).to have_attributes(content: 'Texto original', content_attributes: include('reaction' => { 'emoji' => '👍' }))
        end
        expect(WhatsappUnifiedEvent.last).to have_attributes(state: 'completed', reason: 'mutation_applied', payload: {})
      end
    end
  end

  %w[unoapi whatsapp_cloud].each do |transport|
    context "when a customer reacts to an outgoing message via #{transport}" do
      let(:provider) { transport }
      let(:operation) { 'reaction' }
      let(:value) do
        payload = event.except(:to, :to_user_id).merge(from: '5581981829525')
        { messages: [payload] }.with_indifferent_access
      end

      def event_meta_id
        'wamid.HBgMNTU4MTgxODI5NTI1FQIAEhgUM0E0RUQxQ0FCRDRCRTI1NkU1MEMA'
      end

      it 'keeps a resolved conversation closed, including attachments and the original bubble on duplicate delivery' do
        conversation.update!(status: :resolved)
        stored.attachments.create!(account: account, file_type: :image,
                                   file: { io: File.open(Rails.root.join('spec/assets/avatar.png')), filename: 'preservado.png' })
        snapshot = inventory
        2.times { ingest }
        expect(inventory).to eq(snapshot)
        expect(stored.reload.content_attributes.dig('reaction', 'emoji')).to eq('👍')
        expect(stored.content).to eq('Texto original')
        expect(conversation.reload).to be_resolved
        expect(WhatsappUnifiedEvent.last.state).to eq('completed')
      end

      it 'holds an unknown reference and replays it only after the exact original becomes available' do
        value[:messages].first[:reaction][:message_id] = 'unknown-reaction-target'
        snapshot = inventory
        ingest
        pending = WhatsappUnifiedEvent.last
        expect(pending.state).to eq('pending')
        expect(inventory).to eq(snapshot)
        identity = WhatsappMessageIdentity.create!(account: account, inbox: channel.inbox, channel: channel, provider: provider,
                                                   external_id: 'unknown-reaction-target', provider_message_id: record.original_id,
                                                   observations: { 'business_number' => channel.phone_number, 'direction' => 'outgoing',
                                                                   'participants' => { 'to' => contact.phone_number.delete_prefix('+') } })
        record.aliases.create!(whatsapp_message_identity: identity)
        pending.update!(next_attempt_at: Time.current)
        Whatsapp::UnifiedEventService.new(event: pending).perform
        expect(pending.reload.state).to eq('completed')
        expect(stored.reload.content_attributes.dig('reaction', 'emoji')).to eq('👍')
        expect(inventory).to eq(snapshot)
      end

      it 'removes the reaction without creating a bubble and ignores a late older reaction' do
        ingest
        removal = value.deep_dup
        removal[:messages].first.merge!(id: 'wamid.HBgMNTU4MTgxODI5NTI1FQIAEhgUM0FFQkJCM0M3ODY2MTI5QTI0OUEA',
                                        timestamp: (Time.current.to_i + 1).to_s)
        removal[:messages].first[:reaction][:emoji] = ''
        removal[:messages].first[:provider_message_id] = 'REACTIONREMOVAL123456'
        snapshot = inventory
        2.times { ingest(removal) }
        late = value.deep_dup
        late[:messages].first[:id] = 'wamid.HBgMNTU4MTgxODI5NTI1FQIAEhgUM0FDODVDMzg5NDk5NkU3M0UxOUMA'
        late[:messages].first[:provider_message_id] = 'LATEREACTION12345678'
        ingest(late)
        expect(stored.reload.content_attributes['reaction']).to be_nil
        expect(inventory).to eq(snapshot)
      end

      it 'does not apply reactions from another contact' do
        payload = value.deep_dup
        payload[:messages].first[:from] = '5566991111111'
        snapshot = inventory
        ingest(payload)
        expect(stored.reload.content_attributes['reaction']).to be_nil
        expect(inventory).to eq(snapshot)
      end

      it 'keeps a missing target ID for review without creating contacts, conversations or messages' do
        value[:messages].first[:reaction].delete(:message_id)
        snapshot = inventory
        ingest
        expect(inventory).to eq(snapshot)
        expect(stored.reload.content_attributes['reaction']).to be_nil
        expect(WhatsappUnifiedEvent.last).to have_attributes(state: 'review', reason: 'mutation_target_missing')
      end

      it 'preserves a local operator reaction when an incoming removal arrives' do
        stored.update!(content_attributes: stored.content_attributes.merge('reaction' => { 'emoji' => '❤️' }))
        payload = value.deep_dup
        payload[:messages].first[:reaction][:emoji] = ''
        ingest(payload)
        expect(stored.reload.content_attributes.dig('reaction', 'emoji')).to eq('❤️')
      end

      it 'does not let an edit timestamp suppress a later received reaction and keeps the edit clock unchanged' do
        stored.update!(content_attributes: stored.content_attributes.merge('whatsapp_mutation_timestamp' => mutation_clock = 9_999_999_999_999))
        ingest
        expect(stored.reload.content_attributes).to include('reaction' => { 'emoji' => '👍' }, 'whatsapp_mutation_timestamp' => mutation_clock)
      end

      it 'does not react to a private message' do
        stored.update!(private: true)
        snapshot = inventory
        ingest
        expect(stored.reload.content_attributes['reaction']).to be_nil
        expect(inventory).to eq(snapshot)
      end

      it 'does not react to a group conversation via the direct-contact mutation path' do
        conversation.update!(group: true, group_source_id: '123456789@g.us')
        snapshot = inventory
        ingest
        expect(stored.reload.content_attributes['reaction']).to be_nil
        expect(inventory).to eq(snapshot)
      end

      it 'keeps a single annotation when the same customer reaction also arrives through the partner' do
        conversation.update!(status: :resolved)
        snapshot = inventory
        ingest
        partner = provider == 'unoapi' ? meta : uno
        payload = value.deep_dup
        payload[:messages].first.merge!(id: provider == 'unoapi' ? event_meta_id : 'uno-partner-reaction',
                                        provider_message_id: '3A4ED1CABD4BE256E51C')
        payload[:messages].first[:reaction][:message_id] = provider == 'unoapi' ? original_meta_id : stored.source_id
        service = provider == 'unoapi' ? Whatsapp::IncomingMessageWhatsappCloudService : Whatsapp::IncomingMessageUnoapiService
        params = { entry: [{ changes: [{ field: 'messages', value: payload }] }] }.with_indifferent_access
        2.times { service.new(inbox: partner.inbox, params: params).perform }
        expect(inventory).to eq(snapshot)
        expect(stored.reload.content_attributes.dig('reaction', 'emoji')).to eq('👍')
        expect(WhatsappUnifiedEvent.where(state: 'completed').count).to eq(2)
        expect(conversation.reload).to be_resolved
      end

      it 'requires a reliable event timestamp and keeps the unresolved reaction for review' do
        value[:messages].first.delete(:timestamp)
        snapshot = inventory
        ingest
        expect(inventory).to eq(snapshot)
        expect(WhatsappUnifiedEvent.last).to have_attributes(state: 'review', reason: 'reaction_timestamp_missing')
      end
    end
  end

  it 'defers a missing target without touching a recent unrelated message, then replays after exact evidence arrives' do
    record.update!(message: nil)
    before_inventory = inventory
    ingest
    expect(inventory).to eq(before_inventory)
    expect(stored.reload.content).to eq('Texto original')
    pending = WhatsappUnifiedEvent.last
    expect(pending.state).to eq('pending')
    record.update!(message: stored)
    pending.update!(next_attempt_at: Time.current)
    Whatsapp::UnifiedEventService.new(event: pending).perform
    expect(pending.reload).to have_attributes(state: 'completed', attempts: 1)
    expect(stored.reload.content).to eq('Texto editado sintético')
    expect(inventory).to eq(before_inventory)
  end

  it 'does not revive deleted content when an edit arrives after a revoke' do
    stored.update!(content_attributes: stored.content_attributes.merge('deleted' => true))
    before_attributes = stored.reload.attributes
    ingest
    expect(stored.reload.attributes).to eq(before_attributes)
    expect(WhatsappUnifiedEvent.last.state).to eq('completed')
  end

  it 'does not apply an older edit' do
    stored.update!(content_attributes: stored.content_attributes.merge('whatsapp_mutation_timestamp' => (Time.current.to_i + 60) * 1000))
    before_attributes = stored.reload.attributes
    ingest
    expect(stored.reload.attributes).to eq(before_attributes)
  end

  it 'holds mismatched contact evidence without importing a contact or creating a conversation' do
    contact.update!(phone_number: '+5566991111111')
    before_inventory = inventory
    ingest
    expect(inventory).to eq(before_inventory)
    expect(stored.reload.content).to eq('Texto original')
    expect(WhatsappUnifiedEvent.last.state).to eq('pending')
  end

  it 'keeps malformed references for review instead of selecting a nearby bubble' do
    event[:edit].delete(:original_message_id)
    event[:context] = { id: original_meta_id }
    before_inventory = inventory
    ingest
    expect(inventory).to eq(before_inventory)
    expect(stored.reload.content).to eq('Texto original')
    expect(WhatsappUnifiedEvent.last).to have_attributes(state: 'review', reason: 'mutation_target_missing')
  end

  %w[private direction group].each do |conflict|
    it "does not mutate a target with incompatible #{conflict} evidence" do
      case conflict
      when 'private' then stored.update!(private: true)
      when 'direction' then stored.update!(message_type: :incoming)
      when 'group' then conversation.update!(group: true, group_source_id: '123456789@g.us')
      end
      before_inventory = inventory
      ingest
      expect(inventory).to eq(before_inventory)
      expect(stored.reload.content).to eq('Texto original')
      expect(WhatsappUnifiedEvent.last.state).to eq('pending')
    end
  end

  it 'updates a caption without changing the attachment, blob or original message ID' do
    stored.attachments.create!(account: account, file_type: :image,
                               file: { io: File.open(Rails.root.join('spec/assets/avatar.png')), filename: 'preservado.png' })
    event[:edit][:message] = { type: 'image', image: { caption: 'Legenda editada' } }
    before_inventory = inventory
    ingest
    expect(stored.reload.content).to eq('Legenda editada')
    expect(inventory).to eq(before_inventory)
  end

  it 'applies edit then revoke echoes on the same bubble and honors deleted-content preservation' do
    account.update!(show_deleted_message_content: true)
    before_inventory = inventory
    ingest
    deletion = value.deep_dup
    deletion[:message_echoes].first.merge!(id: 'wamid.HBgTQlIuMTQ3MjQ1MjQ2NDExOTAzOBUUABEYFjNFQjAyRkQ2REYxODE1NjVFMEYyNjQA',
                                           type: 'revoke', revoke: { original_message_id: original_meta_id })
    deletion[:message_echoes].first.delete(:edit)
    2.times { ingest(deletion) }
    expect(inventory).to eq(before_inventory)
    expect(stored.reload.content).to eq('Texto editado sintético')
    expect(stored.content_attributes).to include('deleted' => true, 'deleted_content_preserved' => true,
                                                 'previous_content' => 'Texto original')
    expect(WhatsappUnifiedEvent.where(state: 'completed').count).to eq(2)
  end

  it 'does not apply a mutation when its original reference points to two persisted bubbles' do
    secondary_conversation = create(:conversation, account: account, inbox: meta.inbox, contact: contact)
    shadow = create(:message, account: account, inbox: meta.inbox, conversation: secondary_conversation, message_type: :outgoing,
                              source_id: original_meta_id, content: 'Outra bolha preservada')
    Whatsapp::MessageIdentityObservationService.new(inbox: meta.inbox, outgoing_echo: true,
                                                    value: { message_echoes: [event.merge(id: original_meta_id, type: 'text')] }).perform
    before_inventory = inventory
    ingest
    expect(inventory).to eq(before_inventory)
    expect(stored.reload.content).to eq('Texto original')
    expect(shadow.reload.content).to eq('Outra bolha preservada')
    expect(WhatsappUnifiedEvent.last).to have_attributes(state: 'review', reason: 'correlation_conflict')
  end

  it 'does not replay a pending mutation after the link activation changes' do
    record.update!(message: nil)
    ingest
    pending = WhatsappUnifiedEvent.last
    link.update!(enabled: false)
    before_inventory = inventory
    pending.update!(next_attempt_at: Time.current)
    Whatsapp::UnifiedEventService.new(event: pending).perform
    expect(pending.reload).to have_attributes(state: 'review', reason: 'link_changed')
    expect(inventory).to eq(before_inventory)
    expect(stored.reload.content).to eq('Texto original')
  end

  it 'treats revoke as terminal even when its seconds precision sorts before a millisecond edit' do
    stored.update!(content_attributes: stored.content_attributes.merge('whatsapp_mutation_timestamp' => (Time.current.to_i * 1000) + 999))
    deletion = value.deep_dup
    deletion[:message_echoes].first.merge!(type: 'revoke', revoke: { original_message_id: original_meta_id })
    deletion[:message_echoes].first.delete(:edit)
    before_inventory = inventory
    ingest(deletion)
    expect(stored.reload.content_attributes['deleted']).to be(true)
    expect(inventory).to eq(before_inventory)
  end

  it 'handles the Uno deleted receipt against the canonical bubble without importing receipt contacts' do
    receipt = {
      statuses: [{ id: stored.source_id, provider_message_id: record.original_id, status: 'deleted',
                   recipient_id: '5581981829525', timestamp: Time.current.to_i.to_s }],
      contacts: [{ wa_id: '558188985300', profile: { name: 'Dispositivo comercial, não importar' } }]
    }
    params = { entry: [{ changes: [{ field: 'messages', value: receipt }] }] }.with_indifferent_access
    before_inventory = inventory
    Whatsapp::IncomingMessageUnoapiService.new(inbox: uno.inbox, params: params).perform
    expect(inventory).to eq(before_inventory)
    expect(stored.reload.content_attributes['deleted']).to be(true)
  end

  it 'edits a resolved conversation without reopening it or creating a new cycle' do
    conversation.update!(status: :resolved)
    before_inventory = inventory
    ingest
    expect(inventory).to eq(before_inventory)
    expect(stored.reload.content).to eq('Texto editado sintético')
    expect(conversation.reload).to be_resolved
  end
end
