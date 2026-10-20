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
channel = FactoryBot.create(:channel_whatsapp, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
inbox = channel.inbox
value = {
  messaging_product: 'whatsapp', metadata: { phone_number_id: channel.phone_number },
  contacts: [{ wa_id: '5511999999999', profile: { name: 'Provider identity test' } }],
  messages: [{ from: '5511999999999', id: 'uno-first', provider_message_id: 'ProtocolCaseSensitive',
               type: 'text', text: { body: 'Local fixture' }, timestamp: '1792110000' }]
}.with_indifferent_access
service = Whatsapp::IncomingMessageUnoapiService
service.new(inbox: inbox, params: value).perform
message = inbox.messages.find_by!(source_id: 'uno-first')
identity = WhatsappMessageIdentity.find_by!(inbox: inbox, external_id: 'uno-first')
assert.call(identity.provider_message_id == 'ProtocolCaseSensitive', 'opaque original ID persisted')
assert.call(identity.messages.pluck(:id) == [message.id], 'received message association')
assert.call(identity.account_id == inbox.account_id && identity.channel_id == channel.id, 'account/channel scope')
before_count = inbox.messages.count
service.new(inbox: inbox, params: value).perform
assert.call(inbox.messages.count == before_count && identity.message_links.count == 1, 'repeated webhook has no extra bubbles or links')
assert.call(message.reload.source_id == 'uno-first', 'source_id unchanged')

legacy = value.deep_dup
legacy[:messages][0].delete(:provider_message_id)
legacy[:messages][0][:id] = 'uno-legacy'
service.new(inbox: inbox, params: legacy).perform
assert.call(inbox.messages.exists?(source_id: 'uno-legacy'), 'old payload remains accepted')
assert.call(!WhatsappMessageIdentity.exists?(inbox: inbox, external_id: 'uno-legacy'), 'no invented original identity for old events')

status = { statuses: [{ id: 'uno-early', provider_message_id: 'OriginalEarly', status: 'read', timestamp: '1792110001' }] }
service.new(inbox: inbox, params: status.with_indifferent_access).perform
pending = WhatsappMessageIdentity.find_by!(inbox: inbox, external_id: 'uno-early')
assert.call(pending.messages.empty?, 'status before message retained without bubble')
early = legacy.deep_dup
early[:messages][0][:id] = 'uno-early'
service.new(inbox: inbox, params: early).perform
assert.call(pending.messages.count == 1 && pending.reload.provider_message_id == 'OriginalEarly', 'pending status linked when legacy message arrives')
assert.call(pending.observations.dig('statuses', 'read') == '1792110001', 'raw status timestamp retained')

quote = value.deep_dup
quote[:messages][0].merge!(id: 'uno-quote', provider_message_id: 'OriginalQuote',
                           context: { id: 'uno-first', message_id: 'uno-first', provider_message_id: 'ProtocolCaseSensitive' })
service.new(inbox: inbox, params: quote).perform
quoted = WhatsappMessageIdentity.find_by!(inbox: inbox, external_id: 'uno-quote')
assert.call(quoted.observations.dig('context', 'provider_message_id') == 'ProtocolCaseSensitive', 'quoted original belongs to context, not event')
assert.call(quoted.provider_message_id == 'OriginalQuote', 'event and quoted target remain distinct')
assert.call(inbox.messages.find_by!(source_id: 'uno-quote').content_attributes['in_reply_to_external_id'] == 'uno-first',
            'quote keeps existing operational reference')

conflict = value.deep_dup
conflict[:messages][0][:provider_message_id] = 'ConflictingOriginal'
service.new(inbox: inbox, params: conflict).perform
identity.reload
assert.call(identity.provider_message_id == 'ProtocolCaseSensitive', 'conflict never overwrites known identity')
assert.call(identity.observations['conflicting_provider_message_ids'] == ['ConflictingOriginal'], 'conflict retained for observation')

conversation = message.conversation
optimistic = FactoryBot.create(:message, account: inbox.account, inbox: inbox, conversation: conversation,
                                         source_id: nil, message_type: :outgoing, status: :progress)
observer = Whatsapp::MessageIdentityObservationService
observer.new(inbox: inbox,
             value: { statuses: [{ id: 'uno-send', provider_message_id: 'OriginalSend', status: 'sent',
                                   timestamp: '1792110002' }] }).perform
optimistic.update!(source_id: 'uno-send')
assert.call(optimistic.whatsapp_message_identities.first.provider_message_id == 'OriginalSend', 'late API source assignment links early status')
echo = { message_echoes: [{ id: 'uno-send', provider_message_id: 'OriginalSend', to: '5511999999999',
                            from: channel.phone_number, type: 'text', text: { body: 'Local echo' },
                            timestamp: '1792110002' }] }.with_indifferent_access
before_count = inbox.messages.count
service.new(inbox: inbox, params: echo, outgoing_echo: true).perform
assert.call(inbox.messages.count == before_count, 'echo reuses optimistic message without duplicate')
assert.call(optimistic.whatsapp_message_identities.first.observations['direction'] == 'outgoing', 'echo direction retained')

phone_echo = value.deep_dup
phone_echo[:metadata][:display_phone_number] = channel.phone_number
phone_echo[:messages][0].merge!(id: 'uno-phone-echo', provider_message_id: 'OriginalPhoneEcho', from: channel.phone_number.delete_prefix('+'))
service.new(inbox: inbox, params: phone_echo).perform
phone_identity = WhatsappMessageIdentity.find_by!(inbox: inbox, external_id: 'uno-phone-echo')
assert.call(phone_identity.observations['direction'] == 'outgoing', 'generic messages echo matches existing direction resolver')
assert.call(inbox.messages.find_by!(source_id: 'uno-phone-echo').outgoing?, 'generic echo remains outgoing in legacy model')

contact_copy = FactoryBot.create(:message, account: inbox.account, inbox: inbox, conversation: conversation,
                                           source_id: 'uno-first', message_type: :incoming)
assert.call(identity.message_links.reload.pluck(:message_id).sort == [message.id, contact_copy.id].sort,
            'one transport identity may link multiple legacy contact bubbles')

other = FactoryBot.create(:channel_whatsapp, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
observer.new(inbox: other.inbox, value: value).perform
other_identity = WhatsappMessageIdentity.find_by!(inbox: other.inbox, external_id: 'uno-first')
assert.call(other_identity.id != identity.id && other_identity.messages.empty?, 'same external ID isolated between accounts/inboxes')
invalid = WhatsappMessageIdentityLink.new(whatsapp_message_identity: other_identity, message: message)
assert.call(!invalid.valid?, 'cross-account message link rejected')

threads = Array.new(2) do
  Thread.new do
    ActiveRecord::Base.connection_pool.with_connection do
      observer.new(inbox: inbox, value: { statuses: [{ id: 'uno-concurrent', provider_message_id: 'OriginalConcurrent', status: 'read' }] }).perform
    end
  end
end
threads.each(&:value)
assert.call(WhatsappMessageIdentity.where(inbox: inbox, external_id: 'uno-concurrent').count == 1, 'concurrent observation has one identity')

meta = FactoryBot.create(:channel_whatsapp, account: inbox.account, phone_number: channel.phone_number.delete_prefix('+'),
                                            provider: 'whatsapp_cloud', sync_templates: false,
                                            validate_provider_config: false)
wamid = 'wamid.HBgMNTU2Njk2MjY5MjUxFQIAEhgUM0E4NkEzQUM3QzFDN0JDRTM4ODEA'
observer.new(inbox: meta.inbox, value: { statuses: [{ id: wamid, status: 'read', timestamp: '1792110003' }] }).perform
meta_identity = WhatsappMessageIdentity.find_by!(inbox: meta.inbox, external_id: wamid)
assert.call(meta_identity.provider_message_id == '3A86A3AC7C1C7BCE3881', 'recognized Meta envelope yields original ID')
assert.call(meta_identity.external_id == wamid, 'full wamid unchanged')

observer.new(inbox: inbox,
             value: { statuses: [{ id: 'uno-first', provider_message_id: 'ProtocolCaseSensitive', status: 'deleted',
                                   timestamp: '1792110004' }] }).perform
assert.call(identity.reload.observations.dig('statuses', 'deleted') == '1792110004', 'deletion identity refers to existing target')
observer.new(inbox: inbox, value: {
               messages: [{ id: 'uno-edit-event', provider_message_id: 'OriginalEditEvent', type: 'text',
                            message_type: 'message_edit', edit_timestamp: 1_792_110_005_000,
                            context: { id: 'uno-first', provider_message_id: 'ProtocolCaseSensitive' },
                            text: { body: 'not persisted in observations' } }]
             }).perform
edit = WhatsappMessageIdentity.find_by!(inbox: inbox, external_id: 'uno-edit-event')
assert.call(edit.observations['event_type'] == 'message_edit' && edit.observations['edit_timestamp'] == 1_792_110_005_000,
            'edit event type and raw timestamp retained')
assert.call(edit.messages.empty? && edit.provider_message_id == 'OriginalEditEvent', 'unrendered edit event is not an alias for target message')
assert.call(edit.observations.to_json.exclude?('not persisted in observations'), 'observation never stores message body')
observer.new(inbox: inbox, value: {
               messages: [{ id: 'uno-reaction-event', provider_message_id: 'OriginalReactionEvent', type: 'reaction',
                            reaction: { message_id: 'uno-first', provider_message_id: 'ProtocolCaseSensitive', emoji: '👍' } }]
             }).perform
reaction = WhatsappMessageIdentity.find_by!(inbox: inbox, external_id: 'uno-reaction-event')
assert.call(reaction.observations.dig('reaction', 'provider_message_id') == 'ProtocolCaseSensitive',
            'reaction target kept separate from reaction event')
assert.call(!WhatsappMessageIdentity.new.valid?, 'incomplete identity returns validation errors instead of exception')
assert.call(!WhatsappMessageIdentityLink.new.valid?, 'incomplete link returns validation errors instead of exception')

adapter = Whatsapp::MetaMessageIdAdapter
real_outgoing = 'wamid.HBgMNTU2Njk2MjY5MjUxFQIAERgUQ0VGMEM2MDE2RjBGM0NDQTkzNjYA'
assert.call(adapter.parse(real_outgoing)['provider_message_id'] == 'CEF0C6016F0F3CCA9366', 'real outgoing envelope recognized')
assert.call(adapter.parse(wamid)['participant'] == '556696269251', 'real incoming envelope participant preserved')
assert.call(adapter.parse(wamid)['version'] == adapter::VERSION, 'adapter provenance version retained')
envelope = Base64.strict_decode64(wamid.delete_prefix('wamid.'))
envelope_id = ->(bytes) { "wamid.#{Base64.strict_encode64(bytes)}" }
invalid_envelopes = [envelope[0...-1], "#{envelope}\x00", envelope.sub("\x1c\x18", "\x1d\x18"),
                     envelope.sub("\x15\x02\x00", "\x15\x03\x00"), envelope.sub("\x12\x18", "\x13\x18"),
                     envelope.sub('3A86', '3a86'), envelope.sub("\x18\x14", "\x18\x13"),
                     envelope.sub("\x18\x0c", "\x18\x0b"), envelope.sub('556696269251', 'BR.696269251')]
invalid_envelopes.each_with_index do |bytes, index|
  assert.call(adapter.parse(envelope_id.call(bytes)).nil?, "malformed full envelope rejected #{index}")
end
[nil, '', 'wamid.', 'wamid.%%%', 'wamid.A', 'wamid.ID', "#{wamid}\n", "#{wamid}=", "wamid.#{'A' * 513}"].each_with_index do |invalid_id, index|
  assert.call(adapter.parse(invalid_id).nil?, "invalid encoding rejected #{index}")
end
%w[ABCDEF1234567890 3EB0E87394970CF0F0B535 A5D5052B5ACDD7E57BE697FE979E894C].each do |original|
  bytes = "\x1c\x18\x0c556696269251\x15\x02\x00\x12\x18#{original.bytesize.chr}#{original}\x00".b
  encoded = envelope_id.call(bytes)
  assert.call(adapter.parse(encoded)['provider_message_id'] == original, "known original length #{original.size} accepted")
  assert.call(adapter.parse(encoded.delete_suffix('==').delete_suffix('='))['provider_message_id'] == original,
              "unpadded encoding length #{original.size} accepted")
end

pair_id = '3A86A3AC7C1C7BCE3881'
pair_value = { messages: [{ id: 'uno-pair', provider_message_id: pair_id, from: '556696269251', type: 'text' }] }
meta_value = { messages: [{ id: wamid, from: '556696269251', type: 'text' }] }
observer.new(inbox: inbox, value: pair_value).perform
pair = WhatsappMessageIdentity.find_by!(inbox: inbox, external_id: 'uno-pair')
correlator = Whatsapp::MessageIdentityCorrelationService
assert.call(correlator.new(identity: pair, partner_inbox: meta.inbox).perform[:status] == 'participant_identity_pending',
            'status-only Meta identity remains pending without participant')
observer.new(inbox: meta.inbox, value: meta_value).perform
assert.call(correlator.new(identity: pair, partner_inbox: meta.inbox).perform[:status] == 'matched', 'Uno first then Meta correlates')
assert.call(correlator.new(identity: meta_identity.reload, partner_inbox: inbox).perform[:status] == 'matched',
            'correlation is symmetric without cross-inbox message links')
assert.call(correlator.new(identity: pair, partner_inbox: other.inbox).perform[:status] == 'invalid_scope', 'other account rejected')
assert.call(correlator.new(identity: pair, partner_inbox: inbox).perform[:status] == 'invalid_scope', 'same inbox rejected')

unknown_id = 'wamid.unrecognized'
observer.new(inbox: meta.inbox, value: { statuses: [{ id: unknown_id, provider_message_id: pair_id, status: 'sent' }] }).perform
unknown = WhatsappMessageIdentity.find_by!(inbox: meta.inbox, external_id: unknown_id)
assert.call(unknown.provider_message_id.nil? && unknown.observations.dig('meta_id_adapter', 'status') == 'unrecognized',
            'unknown Meta envelope never trusts unsolicited original ID')
assert.call(correlator.new(identity: unknown, partner_inbox: inbox).perform[:status] == 'original_id_pending', 'unknown ID stays pending')

meta.update!(phone_number: '+5511888888888')
assert.call(correlator.new(identity: pair, partner_inbox: meta.inbox).perform[:status] == 'business_identity_pending',
            'different business number cannot correlate')
meta.update!(phone_number: channel.phone_number.delete_prefix('+'))
meta.inbox.reload # A subsequent webhook request loads the updated channel configuration.
observer.new(inbox: inbox, value: { messages: [{ id: 'uno-pair-bsuid', provider_message_id: 'ABCDEF1234567890',
                                                 from_user_id: 'BR.123456789', type: 'text' }] }).perform
incomplete = WhatsappMessageIdentity.find_by!(inbox: inbox, external_id: 'uno-pair-bsuid')
incomplete_wamid = envelope_id.call("\x1c\x18\x0c556696269251\x15\x02\x00\x12\x18\x10ABCDEF1234567890\x00".b)
observer.new(inbox: meta.inbox, value: { messages: [{ id: incomplete_wamid, from: '556696269251', type: 'text' }] }).perform
diagnostic = correlator.new(identity: incomplete, partner_inbox: meta.inbox).perform
assert.call(diagnostic[:status] == 'participant_identity_pending' && diagnostic[:candidate_identity_ids].one?,
            'own message original locates candidate for incomplete contact without merging')
ninth_wamid = envelope_id.call("\x1c\x18\x0c556696269251\x15\x02\x00\x12\x18\x10ABCDEF1234567891\x00".b)
observer.new(inbox: meta.inbox, value: { messages: [{ id: ninth_wamid, from: '556696269251', type: 'text' }] }).perform
observer.new(inbox: inbox, value: { messages: [{ id: 'uno-ninth', provider_message_id: 'ABCDEF1234567891',
                                                 from: '5566996269251', type: 'text' }] }).perform
ninth = WhatsappMessageIdentity.find_by!(inbox: inbox, external_id: 'uno-ninth')
assert.call(correlator.new(identity: ninth, partner_inbox: meta.inbox).perform[:status] == 'matched',
            'Brazil mobile ninth-digit variant compares equally without merging contacts')

reverse_value = { message_echoes: [{ id: real_outgoing, to: '556696269251', type: 'text' }] }
observer.new(inbox: meta.inbox, value: reverse_value).perform
reverse_meta = WhatsappMessageIdentity.find_by!(inbox: meta.inbox, external_id: real_outgoing)
assert.call(correlator.new(identity: reverse_meta, partner_inbox: inbox).perform[:status] == 'no_candidate', 'Meta first remains observable')
outgoing_value = { message_echoes: [{ id: 'uno-reverse', provider_message_id: 'CEF0C6016F0F3CCA9366', to: '556696269251', type: 'text' }] }
observer.new(inbox: inbox, value: outgoing_value).perform
assert.call(correlator.new(identity: reverse_meta, partner_inbox: inbox).perform[:status] == 'matched', 'Meta first then Uno correlates')
assert.call(reverse_meta.observations.dig('meta_id_adapter', 'direction') == 'outgoing', 'envelope direction retained as evidence')

counts_before = [Message.count, Conversation.count, Contact.count, Attachment.count, WhatsappMessageIdentityLink.count]
snapshot_before = Message.order(:id).pluck(:id, :source_id)
3.times { correlator.new(identity: reverse_meta, partner_inbox: inbox).perform }
assert.call(counts_before == [Message.count, Conversation.count, Contact.count, Attachment.count, WhatsappMessageIdentityLink.count],
            'repeated correlation has no domain writes or media side effects')
assert.call(snapshot_before == Message.order(:id).pluck(:id, :source_id), 'all operational message IDs untouched by correlation')

observer.new(inbox: inbox, value: { statuses: [{ id: 'uno-reverse', provider_message_id: 'CEF0C6016F0F3CCA9366',
                                                 recipient_id: '5511888888888', status: 'read' }] }).perform
assert.call(correlator.new(identity: reverse_meta, partner_inbox: inbox).perform[:status] == 'conflicting_observations',
            'echo to and status recipient mismatch blocks correlation')
stale_meta = WhatsappMessageIdentity.find(reverse_meta.id)
observer.new(inbox: meta.inbox, value: { message_echoes: [{ id: real_outgoing, to: '5511888888888', type: 'text' }] }).perform
assert.call(correlator.new(identity: stale_meta, partner_inbox: inbox).perform[:status] == 'conflicting_observations',
            'query refreshes stale source before considering persisted conflicts')

observer.new(inbox: inbox, value: { message_echoes: [{ id: 'uno-reverse', provider_message_id: 'CEF0C6016F0F3CCA9366',
                                                       to: nil, type: nil }] }).perform
reverse_uno = WhatsappMessageIdentity.find_by!(inbox: inbox, external_id: 'uno-reverse')
assert.call(reverse_uno.observations.dig('participants', 'to') == '556696269251' && reverse_uno.observations['message_type'] == 'text',
            'blank updates never erase known participant/type')
observer.new(inbox: inbox, value: { message_echoes: [{ id: 'uno-reverse', provider_message_id: 'CEF0C6016F0F3CCA9366',
                                                       to: '5511888888888', type: 'text' }] }).perform
assert.call(correlator.new(identity: reverse_meta, partner_inbox: inbox).perform[:status] == 'conflicting_observations',
            'blank intermediate event cannot hide later contradiction')

incomplete_meta = WhatsappMessageIdentity.find_by!(inbox: meta.inbox, external_id: incomplete_wamid)
observer.new(inbox: inbox, value: { message_echoes: [{ id: 'uno-pair-bsuid', provider_message_id: 'ABCDEF1234567890',
                                                       from_user_id: 'BR.123456789', type: 'text' }] }).perform
assert.call(correlator.new(identity: incomplete_meta, partner_inbox: inbox).perform[:status] == 'conflicting_observations',
            'incomplete contact does not hide contradictory directions')

channel.update!(phone_number: '+123456788881')
inbox.reload
observer.new(inbox: inbox, value: pair_value).perform
assert.call(pair.reload.observations['business_number'] != channel.phone_number &&
            pair.observations.dig('conflicting_observations', 'business_number').present?,
            'business observation remains immutable with conflict audit')
assert.call(correlator.new(identity: pair, partner_inbox: meta.inbox).perform[:status] == 'business_identity_pending',
            'channel reconfiguration cannot re-scope old identities')
channel.update!(phone_number: "+#{meta.phone_number}")

observer.new(inbox: inbox, value: { messages: [{ id: 'uno-pair-second', provider_message_id: pair_id,
                                                 from: '556696269251', type: 'text' }] }).perform
assert.call(correlator.new(identity: meta_identity, partner_inbox: inbox).perform[:status] == 'ambiguous', 'reused original not picked arbitrarily')
observer.new(inbox: inbox, value: { messages: [{ id: 'uno-pair', provider_message_id: pair_id, from: '5511888888888', type: 'text' }] }).perform
pair.reload
assert.call(pair.observations.dig('conflicting_observations', 'participants.from').size == 2, 'contradictory participant retained')
assert.call(correlator.new(identity: pair, partner_inbox: meta.inbox).perform[:status] == 'conflicting_observations',
            'latest participant cannot erase conflicting evidence')
assert.call(WhatsappMessageIdentityLink.joins(:whatsapp_message_identity, :message)
            .where('whatsapp_message_identities.inbox_id <> messages.inbox_id').none?, 'correlation creates no cross-inbox links')

mobile_uno = FactoryBot.create(:channel_whatsapp, account: inbox.account, phone_number: '+5566996222471', provider: 'unoapi',
                                                  sync_templates: false, validate_provider_config: false)
mobile_meta = FactoryBot.create(:channel_whatsapp, account: inbox.account, phone_number: '+556696222471', provider: 'whatsapp_cloud',
                                                   sync_templates: false, validate_provider_config: false)
test_wamid = 'wamid.HBgMNTU2Njk2MjY5MjUxFQIAEhgWM0VCMDRBQTFFRDc3ODVENkVEMEYyQQA='
original = '3EB04AA1ED7785D6ED0F2A'
observer.new(inbox: mobile_uno.inbox, value: { messages: [{ id: 'uno-comparison-only', provider_message_id: original,
                                                            from: '5566996269251', type: 'text' }] }).perform
observer.new(inbox: mobile_meta.inbox, value: { messages: [{ id: test_wamid, from: '556696269251', type: 'text' }] }).perform
mobile_left = WhatsappMessageIdentity.find_by!(inbox: mobile_uno.inbox, external_id: 'uno-comparison-only')
mobile_right = WhatsappMessageIdentity.find_by!(inbox: mobile_meta.inbox, external_id: test_wamid)
mobile_comparison = correlator.new(identity: mobile_right, partner_inbox: mobile_uno.inbox)
assert.call(mobile_comparison.perform[:status] == 'matched', 'real test 22 business and participant ninth-digit variants match')
assert.call(correlator.new(identity: mobile_left, partner_inbox: mobile_meta.inbox).perform[:status] == 'matched',
            'normalized mobile comparison is symmetric')
observer.new(inbox: mobile_uno.inbox, value: { messages: [{ id: 'uno-other-original', provider_message_id: 'DifferentOriginal',
                                                            from: '5566996269251', type: 'text' }] }).perform
different_original = WhatsappMessageIdentity.find_by!(inbox: mobile_uno.inbox, external_id: 'uno-other-original')
assert.call(correlator.new(identity: different_original, partner_inbox: mobile_meta.inbox).perform[:status] == 'no_candidate',
            'equal normalized phones cannot replace exact original message ID')

observer.new(inbox: mobile_meta.inbox, value: { message_echoes: [{ id: real_outgoing, to: '556696269251', type: 'text' }] }).perform
observer.new(inbox: mobile_uno.inbox, value: { message_echoes: [{ id: 'uno-mobile-outgoing', provider_message_id: 'CEF0C6016F0F3CCA9366',
                                                                  to: '5566996269251', type: 'text' }] }).perform
observer.new(inbox: mobile_uno.inbox, value: { statuses: [{ id: 'uno-mobile-outgoing', provider_message_id: 'CEF0C6016F0F3CCA9366',
                                                            recipient_id: '556696269251', status: 'read' }] }).perform
mobile_outgoing = WhatsappMessageIdentity.find_by!(inbox: mobile_uno.inbox, external_id: 'uno-mobile-outgoing')
assert.call(correlator.new(identity: mobile_outgoing, partner_inbox: mobile_meta.inbox).perform[:status] == 'matched',
            'echo and status recipient ninth-digit variants compare equally')

phone_cases = { '+556696222471' => '5566996222471', '5566996222471' => '5566996222471',
                '556696269251' => '5566996269251', '551133334444' => '551133334444', '551155554444' => '551155554444',
                '552096222471' => '552096222471', '550096222471' => '550096222471',
                '541196222471' => '541196222471', '14155552671' => '14155552671',
                'BR.1055244414183889' => nil, '94047083475061@lid' => nil, '556696269251@s.whatsapp.net' => nil }
phone_cases.each do |raw, expected_phone|
  assert.call(mobile_comparison.send(:phone, raw) == expected_phone, "comparison phone key #{raw}")
end

observer.new(inbox: mobile_meta.inbox, value: { messages: [{ id: test_wamid, from: '5566996269251', type: 'text' }] }).perform
assert.call(mobile_comparison.perform[:status] == 'matched', 'equivalent historical participant conflict and envelope compare equally')
assert.call(mobile_right.reload.observations.dig('conflicting_observations', 'participants.from').size == 2,
            'raw participant evidence retained even when equivalent')
mobile_meta.update!(phone_number: '5566996222471')
observer.new(inbox: mobile_meta.inbox.reload, value: { messages: [{ id: test_wamid, from: '556696269251', type: 'text' }] }).perform
assert.call(mobile_comparison.perform[:status] == 'matched', 'equivalent business representation change is not a real conflict')
assert.call(mobile_right.reload.observations['business_number'] == '+556696222471', 'observed business number never rewritten')

left_contact = FactoryBot.create(:contact, account: inbox.account, name: 'Existing canonical contact')
right_contact = FactoryBot.create(:contact, account: inbox.account, name: 'Separate legacy contact')
left_conversation = FactoryBot.create(:conversation, account: inbox.account, inbox: mobile_uno.inbox, contact: left_contact)
right_conversation = FactoryBot.create(:conversation, account: inbox.account, inbox: mobile_meta.inbox, contact: right_contact)
left_message = FactoryBot.create(:message, account: inbox.account, inbox: mobile_uno.inbox, conversation: left_conversation,
                                           source_id: 'uno-comparison-only', message_type: :incoming)
right_message = FactoryBot.create(:message, account: inbox.account, inbox: mobile_meta.inbox, conversation: right_conversation,
                                            source_id: test_wamid, message_type: :incoming)
immutable_snapshot = [Message.order(:id).pluck(:id, :source_id, :inbox_id, :conversation_id),
                      Contact.order(:id).pluck(:id, :name, :phone_number),
                      Channel::Whatsapp.order(:id).pluck(:id, :phone_number),
                      WhatsappMessageIdentity.order(:id).pluck(:id, :external_id, :provider_message_id, :observations)]
3.times { assert.call(mobile_comparison.perform[:status] == 'matched', 'comparison does not require equal internal contact IDs') }
assert.call(immutable_snapshot == [Message.order(:id).pluck(:id, :source_id, :inbox_id, :conversation_id),
                                   Contact.order(:id).pluck(:id, :name, :phone_number),
                                   Channel::Whatsapp.order(:id).pluck(:id, :phone_number),
                                   WhatsappMessageIdentity.order(:id).pluck(:id, :external_id, :provider_message_id, :observations)],
            'normalized queries preserve all stored phones, source IDs, observations and contacts')
assert.call(left_message.reload.inbox_id != right_message.reload.inbox_id && left_contact.id != right_contact.id,
            'both inboxes, conversations and contacts remain separate')

observer.new(inbox: mobile_meta.inbox, value: { messages: [{ id: test_wamid, from: '5511888888888', type: 'text' }] }).perform
assert.call(mobile_comparison.perform[:status] == 'conflicting_observations', 'real phone conflict is still rejected after normalization')
mobile_meta.update!(phone_number: '+552096222471')
assert.call(mobile_comparison.perform[:status] == 'business_identity_pending', 'invalid area code cannot authorize a different business number')

message_count = Message.count
load Rails.root.join('db/migrate/20261016000005_create_whatsapp_unified_events.rb')
had_unified_events = ActiveRecord::Base.connection.data_source_exists?(:whatsapp_unified_events)
ActiveRecord::Migration.suppress_messages { CreateWhatsappUnifiedEvents.new.migrate(:down) } if had_unified_events
load Rails.root.join('db/migrate/20261016000004_create_whatsapp_unified_messages.rb')
had_unified_tables = ActiveRecord::Base.connection.data_source_exists?(:whatsapp_unified_messages)
ActiveRecord::Migration.suppress_messages { CreateWhatsappUnifiedMessages.new.migrate(:down) } if had_unified_tables
load Rails.root.join('db/migrate/20261016000002_create_whatsapp_identity_resolutions.rb')
ActiveRecord::Migration.suppress_messages { CreateWhatsappIdentityResolutions.new.migrate(:down) }
assert.call(!ActiveRecord::Base.connection.data_source_exists?(:whatsapp_identity_resolutions),
            'pending-resolution migration rolls back in isolation')
load Rails.root.join('db/migrate/20261016000000_create_whatsapp_message_identities.rb')
ActiveRecord::Migration.suppress_messages { CreateWhatsappMessageIdentities.new.migrate(:down) }
assert.call(!ActiveRecord::Base.connection.data_source_exists?(:whatsapp_message_identities),
            'isolated migration down removes new observation tables')
assert.call(Message.count == message_count, 'migration rollback does not remove legacy messages')
ActiveRecord::Migration.suppress_messages { CreateWhatsappMessageIdentities.new.migrate(:up) }
assert.call(ActiveRecord::Base.connection.data_source_exists?(:whatsapp_message_identity_links), 'isolated migration can be reapplied')
load Rails.root.join('db/migrate/20261016000001_index_whatsapp_message_identity_originals.rb')
ActiveRecord::Migration.suppress_messages { IndexWhatsappMessageIdentityOriginals.new.migrate(:up) }
assert.call(ActiveRecord::Base.connection.indexes(:whatsapp_message_identities).any? { |index| index.name == 'idx_wa_identity_original' },
            'scoped original-ID lookup index can be applied')
ActiveRecord::Migration.suppress_messages { IndexWhatsappMessageIdentityOriginals.new.migrate(:down) }
assert.call(ActiveRecord::Base.connection.indexes(:whatsapp_message_identities).none? { |index| index.name == 'idx_wa_identity_original' },
            'lookup index rollback leaves message identities intact')
ActiveRecord::Migration.suppress_messages { IndexWhatsappMessageIdentityOriginals.new.migrate(:up) }

ActiveRecord::Migration.suppress_messages { CreateWhatsappIdentityResolutions.new.migrate(:up) }
assert.call(ActiveRecord::Base.connection.data_source_exists?(:whatsapp_identity_resolutions),
            'pending-resolution migration reapplies after identities')
if had_unified_tables
  ActiveRecord::Migration.suppress_messages { CreateWhatsappUnifiedMessages.new.migrate(:up) }
  assert.call(ActiveRecord::Base.connection.data_source_exists?(:whatsapp_unified_message_aliases),
              'canonical aliases reapply after identity migration rollback')
end
ActiveRecord::Migration.suppress_messages { CreateWhatsappUnifiedEvents.new.migrate(:up) } if had_unified_events

# Machine-readable CLI report, not an application log.
puts({ result: 'PASS', database: ActiveRecord::Base.connection_db_config.database, checks: checks.size, scenarios: checks }.to_json)
