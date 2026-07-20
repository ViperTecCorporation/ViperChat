# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountUser do
  include ActiveJob::TestHelper

  let!(:account_user) { create(:account_user) }
  let!(:inbox) { create(:inbox, account: account_user.account) }

  describe 'notification_settings' do
    it 'gets created with the right default settings' do
      notification_setting = account_user.user.notification_settings.first

      expect(notification_setting.selected_email_flags).to be_empty
      expect(notification_setting.selected_push_flags).to contain_exactly(
        :push_conversation_assignment,
        :push_conversation_mention,
        :push_assigned_conversation_new_message,
        :push_participating_conversation_new_message,
        :push_sla_missed_first_response,
        :push_sla_missed_next_response,
        :push_sla_missed_resolution
      )
      expect(notification_setting.push_conversation_creation?).to be(false)
    end
  end

  describe 'permissions' do
    it 'returns the right permissions' do
      expect(account_user.permissions).to eq(['agent'])
    end

    it 'returns the right permissions for administrator' do
      account_user.administrator!
      expect(account_user.permissions).to eq(['administrator'])
    end
  end

  describe 'destroy call agent::destroy service' do
    it 'gets created with the right default settings' do
      create(:conversation, account: account_user.account, assignee: account_user.user, inbox: inbox)
      user = account_user.user

      expect(user.assigned_conversations.count).to eq(1)

      perform_enqueued_jobs do
        account_user.destroy!
      end

      expect(user.assigned_conversations.count).to eq(0)
    end
  end
end
