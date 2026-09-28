# frozen_string_literal: true

FactoryBot.define do
  factory :account do
    sequence(:name) { |n| "Account #{n}" }
    status { 'active' }
    domain { 'test.com' }
    support_email { 'support@test.com' }

    trait :with_tiktok do
      after(:create) { |account| account.enable_features!('channel_tiktok') }
    end
  end
end
