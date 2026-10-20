unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database == 'viperchat_provider_identity_test'
  raise 'Wrong database: refusing validation'
end

require 'webmock'
WebMock.enable!
WebMock.disable_net_connect!
ActiveJob::Base.queue_adapter = :test
require 'factory_bot_rails'
FactoryBot.find_definitions unless FactoryBot.factories.registered?(:account)

checks = []
assert = lambda { |condition, label|
  raise "FAILED: #{label}" unless condition

  checks << label
}
adapter = Whatsapp::MetaMessageIdAdapter
raw_wamid = 'wamid.HBgTQlIuMTc2NTk0NjA5MTM1Mjk5NhUUABEYFjNFQjA0NDk2RUZFNTM3NTY0MTJCQjkA'
bsuid = 'BR.1765946091352996'
original = '3EB04496EFE53756412BB9'
parsed = adapter.parse(raw_wamid)
assert.call(parsed['provider_message_id'] == original && parsed['participant'] == bsuid, 'real BSUID envelope original extracted')
assert.call(parsed['participant_type'] == 'bsuid' && parsed['direction'] == 'outgoing', 'namespace and direction retained')
raw = Base64.strict_decode64(raw_wamid.delete_prefix('wamid.'))
encode = ->(bytes) { "wamid.#{Base64.strict_encode64(bytes)}" }
incoming_wamid = encode.call(raw.sub("\x00\x11\x18", "\x00\x12\x18"))
assert.call(adapter.parse(incoming_wamid)['direction'] == 'incoming', 'synthetic incoming BSUID envelope supported')
[raw.sub("\x18\x13", "\x18\x12"), raw.sub("\x15\x14", "\x15\x02"),
 raw.sub('BR.', 'br.'), raw[0...-1], "#{raw}\x00", raw.sub("\x00\x11\x18", "\x00\x13\x18")].each_with_index do |bytes, index|
  assert.call(adapter.parse(encode.call(bytes)).nil?, "malformed BSUID envelope rejected #{index}")
end

uno = FactoryBot.create(:channel_whatsapp, provider: 'unoapi', phone_number: '+5566996222471',
                                           sync_templates: false, validate_provider_config: false)
meta = FactoryBot.create(:channel_whatsapp, account: uno.account, provider: 'whatsapp_cloud', phone_number: '+556696222471',
                                            sync_templates: false, validate_provider_config: false)
old_contact = FactoryBot.create(:contact, account: uno.account, name: 'Established human name', phone_number: '+5566996651924',
                                          bsuid: '22364028932201@lid', additional_attributes: { 'manual_note' => 'preserve' })
conversation = FactoryBot.create(:conversation, account: uno.account, inbox: uno.inbox, contact: old_contact)
uno_message = FactoryBot.create(:message, account: uno.account, inbox: uno.inbox, conversation: conversation,
                                          source_id: 'existing-uno-public-id', message_type: :outgoing)
observer = Whatsapp::MessageIdentityObservationService
observer.new(inbox: uno.inbox, outgoing_echo: true, value: {
               message_echoes: [{ id: uno_message.source_id, provider_message_id: original, from: '5566996222471',
                                  to: '5566996651924', type: 'text' }]
             }).perform
event = { id: raw_wamid, from: '556696222471', to_user_id: bsuid, type: 'text', text: { body: 'Own message, not a quote' } }
observer.new(inbox: meta.inbox, value: { message_echoes: [event] }).perform
resolver = Whatsapp::MessageIdentityContactResolver
contact_count = Contact.count
assert.call(resolver.new(inbox: meta.inbox, message: event).perform.nil?, 'no automatic partner discovery when configuration absent')
meta.update!(provider_config: meta.provider_config.merge(resolver::CONFIG_KEY => uno.inbox.id))
meta.inbox.reload
before_contact = old_contact.reload.attributes
alias_link = resolver.new(inbox: meta.inbox, message: event).perform
assert.call(alias_link.contact_id == old_contact.id && alias_link.source_id == bsuid, 'reuse established contact by own original message')
assert.call(Contact.count == contact_count && old_contact.reload.attributes == before_contact, 'human name phone LID and manual data untouched')
assert.call(alias_link.additional_attributes.dig('message_identity_resolution', 'identity_id').present?, 'alias provenance retained')
assert.call(resolver.new(inbox: meta.inbox, message: event).perform.id == alias_link.id, 'repeat resolver is idempotent')

params = { entry: [{ changes: [{ value: { metadata: { display_phone_number: '556696222471' }, message_echoes: [event] } }] }] }
cloud = Whatsapp::IncomingMessageWhatsappCloudService
before_conversations = Conversation.count
cloud.new(inbox: meta.inbox, params: params.with_indifferent_access, outgoing_echo: true).perform
meta_message = meta.inbox.messages.find_by!(source_id: raw_wamid)
assert.call(meta_message.conversation.contact_id == old_contact.id && meta_message.outgoing?,
            'real ingestion uses canonical contact and outgoing direction')
assert.call(Contact.count == contact_count && Conversation.count == before_conversations + 1, 'no extra contact and separate Meta conversation')
assert.call(meta_message.conversation_id != uno_message.conversation_id && uno_message.reload.source_id == 'existing-uno-public-id',
            'inboxes and old source IDs are not unified')
cloud.new(inbox: meta.inbox, params: params.with_indifferent_access, outgoing_echo: true).perform
assert.call(meta.inbox.messages.where(source_id: raw_wamid).count == 1, 'webhook repetition creates no extra Meta bubble')
assert.call(old_contact.reload.attributes == before_contact, 'ingestion preserves old contact attributes')

results = Array.new(2) do
  Thread.new do
    ActiveRecord::Base.connection_pool.with_connection { resolver.new(inbox: Inbox.find(meta.inbox.id), message: event).perform.id }
  end
end.map(&:value)
assert.call(results.uniq == [alias_link.id] && meta.inbox.contact_inboxes.where(source_id: bsuid).count == 1,
            'concurrent resolvers retain one alias and no duplicate contact')

incoming_event = { id: incoming_wamid, from_user_id: bsuid, type: 'text', text: { body: 'Incoming fixture' } }
incoming_original = '3EB04496EFE53756412BB8'
incoming_wamid = encode.call(Base64.strict_decode64(incoming_wamid.delete_prefix('wamid.')).sub(original, incoming_original))
incoming_event[:id] = incoming_wamid
incoming_uno = FactoryBot.create(:message, account: uno.account, inbox: uno.inbox, conversation: conversation,
                                           source_id: 'incoming-uno-public-id', message_type: :incoming)
observer.new(inbox: uno.inbox, value: { messages: [{ id: incoming_uno.source_id, provider_message_id: incoming_original,
                                                     from: '5566996651924', type: 'text' }] }).perform
incoming_params = { entry: [{ changes: [{ value: { messages: [incoming_event] } }] }] }
cloud.new(inbox: meta.inbox, params: incoming_params.with_indifferent_access).perform
received = meta.inbox.messages.find_by!(source_id: incoming_wamid)
assert.call(received.conversation.contact_id == old_contact.id && received.sender_id == old_contact.id && received.incoming?,
            'incoming BSUID without contacts array reuses established contact')

other_account = FactoryBot.create(:channel_whatsapp, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
meta.update!(provider_config: meta.provider_config.merge(resolver::CONFIG_KEY => other_account.inbox.id))
assert.call(resolver.new(inbox: meta.inbox.reload, message: event).perform.nil?, 'cross-account configuration rejected')
meta.update!(provider_config: meta.provider_config.merge(resolver::CONFIG_KEY => uno.inbox.id))
meta.inbox.reload

pipeline_bsuid = 'BR.1765946091352998'
pipeline_contact_count = Contact.count
pipeline_event = event.merge(id: encode.call(raw.sub(bsuid, pipeline_bsuid)), to_user_id: pipeline_bsuid)
pipeline_params = { entry: [{ changes: [{ value: { message_echoes: [pipeline_event] } }] }] }
cloud.new(inbox: meta.inbox, params: pipeline_params.with_indifferent_access, outgoing_echo: true).perform
assert.call(meta.inbox.contact_inboxes.find_by!(source_id: pipeline_bsuid).contact_id == old_contact.id && Contact.count == pipeline_contact_count,
            'full ingestion creates a new canonical alias before any legacy technical contact')

unknown_original = original.sub(/9\z/, '7')
unknown_event = event.merge(id: encode.call(raw.sub(original, unknown_original)),
                            context: { id: raw_wamid, provider_message_id: original })
observer.new(inbox: meta.inbox, value: { message_echoes: [unknown_event] }).perform
unknown_resolver = resolver.new(inbox: meta.inbox, message: unknown_event)
assert.call(unknown_resolver.perform.nil? && unknown_resolver.status == 'no_candidate',
            'quoted original cannot identify the sender of a different own message')
assert.call(resolver.new(inbox: meta.inbox, message: event.merge(to_user_id: 'BR.9999999999999999')).perform.nil?,
            'envelope BSUID must match the event participant role')
assert.call(resolver.new(inbox: meta.inbox, message: event.merge(type: 'reaction')).perform.nil?, 'reaction target cannot establish contact identity')
meta.update!(phone_number: '+5511888888888')
business_resolver = resolver.new(inbox: meta.inbox.reload, message: event)
assert.call(business_resolver.perform.nil? && business_resolver.status == 'business_identity_pending', 'different business number rejected')
meta.update!(phone_number: '+556696222471')
meta.inbox.reload

late_bsuid = 'BR.1765946091352999'
late_original = original.sub(/9\z/, '6')
late_event = event.merge(id: encode.call(raw.sub(bsuid, late_bsuid).sub(original, late_original)), to_user_id: late_bsuid)
observer.new(inbox: meta.inbox, value: { message_echoes: [late_event] }).perform
late_resolver = resolver.new(inbox: meta.inbox, message: late_event)
assert.call(late_resolver.perform.nil? && late_resolver.status == 'no_candidate', 'Meta-first observation never guesses a contact')
late_uno = FactoryBot.create(:message, account: uno.account, inbox: uno.inbox, conversation: conversation,
                                       source_id: 'late-counterpart-public-id', message_type: :outgoing)
observer.new(inbox: uno.inbox, outgoing_echo: true, value: {
               message_echoes: [{ id: late_uno.source_id, provider_message_id: late_original, to: '5566996651924', type: 'text' }]
             }).perform
assert.call(resolver.new(inbox: meta.inbox, message: late_event).perform.contact_id == old_contact.id,
            'pending identity can resolve when counterpart becomes available without an existing conflicting alias')
old_contact.update!(phone_number: '+5511988888888')
phone_resolver = resolver.new(inbox: meta.inbox, message: late_event)
assert.call(phone_resolver.perform.nil? && phone_resolver.status == 'contact_identity_pending',
            'candidate contact phone must corroborate the counterpart participant')
old_contact.update!(phone_number: '+5566996651924')
meta.inbox.update!(lock_to_single_conversation: true)
retained_conversations = Array.new(2) do
  FactoryBot.create(:conversation, account: uno.account, inbox: meta.inbox, contact: old_contact, contact_inbox: alias_link).id
end
late_params = { entry: [{ changes: [{ value: { message_echoes: [late_event] } }] }] }
cloud.new(inbox: meta.inbox, params: late_params.with_indifferent_access, outgoing_echo: true).perform
assert.call(Conversation.where(id: retained_conversations).count == 2,
            'resolution never merges historical conversations even in single-conversation mode')

conflict_bsuid = 'BR.1765946091352997'
conflict_wamid = encode.call(raw.sub(bsuid, conflict_bsuid))
conflict_event = event.merge(id: conflict_wamid, to_user_id: conflict_bsuid)
observer.new(inbox: meta.inbox, value: { message_echoes: [conflict_event] }).perform
technical_contact = FactoryBot.create(:contact, account: uno.account, name: conflict_bsuid, bsuid: conflict_bsuid)
technical_alias = meta.inbox.contact_inboxes.create!(source_id: conflict_bsuid, contact: technical_contact)
conflict_resolver = resolver.new(inbox: meta.inbox, message: conflict_event)
assert.call(conflict_resolver.perform.nil? && conflict_resolver.status == 'alias_conflict', 'existing duplicate is not silently merged or reassigned')
assert.call(technical_alias.reload.contact_id == technical_contact.id && technical_contact.reload.persisted?,
            'legacy technical contact remains intact')

ambiguous = FactoryBot.create(:message, account: uno.account, inbox: uno.inbox, conversation: conversation,
                                        source_id: 'second-original-public-id', message_type: :outgoing)
observer.new(inbox: uno.inbox, outgoing_echo: true, value: {
               message_echoes: [{ id: ambiguous.source_id, provider_message_id: original, to: '5566996651924', type: 'text' }]
             }).perform
ambiguous_resolver = resolver.new(inbox: meta.inbox, message: event)
assert.call(ambiguous_resolver.perform.nil? && ambiguous_resolver.status == 'ambiguous', 'multiple original candidates never chosen arbitrarily')
assert.call(uno_message.reload.conversation_id == conversation.id && meta_message.reload.conversation.contact_id == old_contact.id,
            'existing messages and conversations never moved by resolver')

# Machine-readable CLI report, not an application log.
puts({ result: 'PASS', database: ActiveRecord::Base.connection_db_config.database, checks: checks.size, scenarios: checks }.to_json)
