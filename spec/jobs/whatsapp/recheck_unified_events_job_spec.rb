require 'rails_helper'

RSpec.describe Whatsapp::RecheckUnifiedEventsJob do
  it 'rechecks old media exceptions without directly reconciling or changing a file' do
    meta = create(:channel_whatsapp, provider: 'whatsapp_cloud', phone_number: '+556696222471', sync_templates: false,
                                     validate_provider_config: false)
    uno = create(:channel_whatsapp, account: meta.account, provider: 'unoapi', phone_number: '+5566996222471', sync_templates: false,
                                    validate_provider_config: false)
    link = WhatsappInboxLink.create!(account: meta.account, primary_inbox: uno.inbox, secondary_inbox: meta.inbox, enabled: true,
                                     default_provider: 'unoapi')
    message = create(:message, account: meta.account, inbox: uno.inbox)
    record = WhatsappUnifiedMessage.create!(whatsapp_inbox_link: link, message: message, original_id: 'synthetic-media-retry', direction: 'outgoing',
                                            participant_key: '5566996269251', message_kind: 'audio', state: 'ready',
                                            media_review_status: 'review', media_review_reason: 'untrusted_mapping')
    travel 6.minutes
    before = record.reload.attributes
    expect { described_class.perform_now }.to have_enqueued_job(Whatsapp::ReconcileUnifiedMediaJob).with(record.id)
    expect(record.reload.attributes).to eq(before)
    clear_enqueued_jobs
    link.update!(enabled: false)
    expect { described_class.perform_now }.not_to have_enqueued_job(Whatsapp::ReconcileUnifiedMediaJob)
  end
end
