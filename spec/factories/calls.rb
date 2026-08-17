# frozen_string_literal: true

FactoryBot.define do
  factory :call do
    association :conversation
    account { conversation.account }
    inbox { conversation.inbox }
    contact { conversation.contact }
    sequence(:provider_call_id) { |number| "CA#{SecureRandom.hex(15)}#{number}" }
    provider { :twilio }
    direction { :incoming }
    status { 'ringing' }
  end
end
