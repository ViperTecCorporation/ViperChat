RSpec.shared_context 'with Uno web attendance' do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', sync_templates: false, validate_provider_config: false,
                              provider_config: { 'url' => 'https://uno.example.com', 'api_key' => 'test_key',
                                                 'phone_number_id' => '556600000000', 'business_account_id' => '556600000000' })
  end
  let(:inbox) do
    channel.inbox.tap { |record| record.update!(web_attendance_enabled: true, enable_auto_assignment: false) }
  end
  let(:contact) { create(:contact, account: account, phone_number: '+5566996269251') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact).reload }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:invitation_service) { WebAttendance::InvitationService.new(conversation: conversation, user: user) }
  let(:invitation_message) { invitation_service.create!(content: 'Continue on the web', request_id: 'invite-request-001') }
  let(:invitation) { conversation.web_attendance_invitations.find_by!(message: invitation_message) }
  let(:invitation_token) { invitation.link.split('#token=').last }
end
