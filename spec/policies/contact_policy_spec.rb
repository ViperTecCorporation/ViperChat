# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ContactPolicy, type: :policy do
  subject(:contact_policy) { described_class }

  let(:account) { create(:account) }

  let(:administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account) }

  let(:administrator_context) { { user: administrator, account: account, account_user: account.account_users.first } }
  let(:agent_context) { { user: agent, account: account, account_user: account.account_users.first } }

  permissions :show? do
    it 'allows same-account contact details without granting access to its inbox or conversation' do
      account.disable_features!('hide_contacts_for_agent')
      account.enable_features!('hide_all_chats_for_agent', 'hide_unassigned_for_agent')
      restricted = create(:conversation, account: account, contact: contact)

      expect(contact_policy).to permit(agent_context, contact)
      expect(ConversationPolicy.new(agent_context, restricted).show?).to be(false)
      allow(Current).to receive(:user).and_return(agent)
      allow(Current).to receive(:account).and_return(account)
      expect(InboxPolicy.new(agent_context, restricted.inbox).show?).to be(false)
    end

    it 'preserves access for an agent bot in its account' do
      context = { user: build(:agent_bot), account: account, account_user: nil }
      expect(contact_policy).to permit(context, contact)
    end

    it 'rejects contacts from another account even for administrators' do
      expect(contact_policy).not_to permit(administrator_context, create(:contact))
    end
  end

  permissions :index?, :show?, :update? do
    context 'when administrator' do
      it { expect(contact_policy).to permit(administrator_context, contact) }
    end

    context 'when agent' do
      before { account.disable_features!('hide_contacts_for_agent') }

      it { expect(contact_policy).to permit(agent_context, contact) }
    end
  end

  permissions :index?, :search?, :filter?, :active? do
    it 'denies the contact directory when hidden for agents' do
      account.enable_features!('hide_contacts_for_agent')
      expect(contact_policy).not_to permit(agent_context, contact)
    end
  end

  permissions :import? do
    it 'denies legacy imports when data import is disabled' do
      account.disable_features!('data_import')
      expect(contact_policy).not_to permit(administrator_context, contact)
    end
  end

  permissions :create? do
    context 'when administrator' do
      it { expect(contact_policy).to permit(administrator_context, contact) }
    end

    context 'when agent' do
      it { expect(contact_policy).to permit(agent_context, contact) }
    end
  end
end
