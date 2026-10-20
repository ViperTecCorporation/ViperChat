require 'rails_helper'

RSpec.describe Whatsapp::UnifiedReviewService do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:uno) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5565987654321',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:meta) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+556587654321',
                              sync_templates: false, validate_provider_config: false)
  end
  let!(:link) do
    WhatsappInboxLink.create!(account: account, primary_inbox: uno.inbox, secondary_inbox: meta.inbox,
                              default_provider: 'unoapi', enabled: true)
  end
  let(:identity) do
    WhatsappMessageIdentity.create!(account: account, inbox: meta.inbox, channel: meta, provider: 'whatsapp_cloud',
                                    external_id: 'wamid.safe-test', provider_message_id: 'original-test')
  end
  let!(:event) do
    WhatsappUnifiedEvent.create!(whatsapp_inbox_link: link, whatsapp_message_identity: identity,
                                activation_cutoff: link.activated_at, state: 'review', reason: 'identity_pending',
                                payload: { secret: 'never expose payload' })
  end
  let(:service) { described_class.new(link: link, actor: actor) }
  let(:item) { service.list[:items].find { |row| row[:id] == "event-#{event.id}" } }

  before do
    WebMock.disable_net_connect!(allow_localhost: false)
    actor
  end

  it 'returns only diagnostic metadata and hides raw payloads' do
    expect(item).to include(kind: 'event', reason: 'identity_pending', public_id: 'wamid.safe-test', original_id: 'original-test')
    expect(item[:actions]).to eq(recheck: true, acknowledge: true)
    expect(service.list.to_json).not_to include('never expose payload', 'secret', 'provider_config')
  end

  it 'acknowledges without completing quarantine or sending anything' do
    clear_enqueued_jobs
    original = event.attributes
    result = service.act(id: item[:id], action: 'acknowledge', version: item[:version])
    expect(event.reload.attributes).to eq(original)
    expect(result[:reviewed_by_id]).to eq(actor.id)
    expect(service.list[:items]).to be_empty
    expect(service.list(status: 'acknowledged')[:items].size).to eq(1)
    expect(enqueued_jobs).to be_empty
    expect(account.contacts.count).to eq(0)
    expect(account.messages.count).to eq(0)
  end

  it 'rejects a repeated stale acknowledgement and retains a single audit action' do
    old = item
    service.act(id: old[:id], action: 'acknowledge', version: old[:version])
    expect { service.act(id: old[:id], action: 'acknowledge', version: old[:version]) }.to raise_error(described_class::Conflict)
    expect(WhatsappUnifiedReviewAction.where(whatsapp_inbox_link: link).count).to eq(1)
  end

  it 'invalidates an acknowledgement when evidence changes' do
    service.act(id: item[:id], action: 'acknowledge', version: item[:version])
    travel 1.second
    event.update!(reason: 'correlation_conflict')
    expect(service.list[:items].sole[:reviewed_at]).to be_nil
    expect(service.list(status: 'acknowledged')[:items]).to be_empty
  end

  it 'only schedules evidence re-evaluation, never performs provider IO in the request' do
    old = item
    clear_enqueued_jobs
    expect do
      service.act(id: old[:id], action: 'recheck', version: old[:version])
    end.to have_enqueued_job(Whatsapp::ProcessUnifiedEventJob).with(event.id)
    expect(event.reload).to have_attributes(state: 'pending', attempts: 0)
    expect(WhatsappUnifiedReviewAction.last).to have_attributes(action: 'recheck', actor_id: actor.id)
    expect(account.messages.count).to eq(0)
  end

  it 'blocks actions from a stale evidence version' do
    old = item
    travel 1.second
    event.update!(reason: 'correlation_conflict')
    expect { service.act(id: old[:id], action: 'recheck', version: old[:version]) }.to raise_error(described_class::Conflict)
  end

  it 'keeps invalidated generations visible but never reprocesses them' do
    link.update!(enabled: false)
    expect(item[:actions]).to eq(recheck: false, acknowledge: true)
    expect { service.act(id: item[:id], action: 'recheck', version: item[:version]) }.to raise_error(described_class::Conflict)
    link.update!(enabled: true)
    expect(item[:actions][:recheck]).to be(false)
  end

  it 'does not find records outside the pair or malformed IDs' do
    expect { service.act(id: "event-#{event.id + 1}", action: 'acknowledge', version: 'x') }.to raise_error(ActiveRecord::RecordNotFound)
    expect { service.act(id: '../1', action: 'acknowledge', version: 'x') }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'validates filters instead of interpolating arbitrary input' do
    expect { service.list(kind: 'sql') }.to raise_error(ArgumentError)
    expect { service.list(status: 'sql') }.to raise_error(ArgumentError)
    expect(service.list(page: -100)[:meta][:page]).to eq(1)
  end

  it 'paginates without losing a record when timestamps coincide' do
    27.times do |index|
      another = identity.dup
      another.external_id = "wamid.test-#{index}"
      another.save!
      WhatsappUnifiedEvent.create!(whatsapp_inbox_link: link, whatsapp_message_identity: another,
                                  activation_cutoff: link.activated_at, state: 'review', reason: 'identity_pending')
    end
    first = service.list
    second = service.list(page: 2)
    expect(first[:meta]).to include(total: 28, total_pages: 2)
    expect(first[:items].size).to eq(25)
    expect(second[:items].size).to eq(3)
    expect((first[:items] + second[:items]).pluck(:id).uniq.size).to eq(28)
  end

  context 'with uncertain outgoing delivery' do
    let(:conversation) { create(:conversation, account: account, inbox: uno.inbox) }
    let!(:message) do
      create(:message, account: account, inbox: uno.inbox, conversation: conversation, message_type: :outgoing,
                       content_attributes: { whatsapp_transport: { link_id: link.id, provider: 'unoapi',
                                                                  delivery_attempt_id: 'claimed', delivery_state: 'uncertain' } })
    end

    it 'never offers retry or fabricates a receipt' do
      row = service.list(kind: 'delivery')[:items].sole
      expect(row[:actions]).to eq(recheck: false, acknowledge: true)
      original = message.reload.attributes
      clear_enqueued_jobs
      service.act(id: row[:id], action: 'acknowledge', version: row[:version])
      expect(message.reload.attributes).to eq(original)
      expect(enqueued_jobs).to be_empty
      expect { service.act(id: row[:id], action: 'recheck', version: row[:version]) }.to raise_error(described_class::Conflict)
    end

    it 'excludes private messages even with forged transport metadata' do
      message.update!(private: true)
      expect(service.list(kind: 'delivery')[:items]).to be_empty
    end
  end

  context 'with a persisted media review result' do
    let(:conversation) { create(:conversation, account: account, inbox: uno.inbox) }
    let!(:message) { create(:message, account: account, inbox: uno.inbox, conversation: conversation) }
    let!(:media) do
      WhatsappUnifiedMessage.create!(whatsapp_inbox_link: link, message: message, original_id: 'media-original',
                                     direction: 'incoming', participant_key: '5565987654321', message_kind: 'image',
                                     state: 'ready', media_review_status: 'review', media_review_reason: 'untrusted_mapping')
    end

    it 'queues media verification without deleting a message or attachment' do
      row = service.list(kind: 'media')[:items].sole
      clear_enqueued_jobs
      expect do
        service.act(id: row[:id], action: 'recheck', version: row[:version])
      end.to have_enqueued_job(Whatsapp::ReconcileUnifiedMediaJob).with(media.id)
      expect(media.reload.media_review_status).to eq('pending')
      expect(message.reload.id).to eq(message.id)
    end
  end

  it 'keeps an unmaterialized historical reservation visible and quarantined after acknowledgement' do
    reservation = WhatsappUnifiedMessage.create!(whatsapp_inbox_link: link, original_id: 'held-original',
                                                participant_key: '5565987654321', direction: 'incoming', message_kind: 'text', state: 'review')
    row = service.list(kind: 'reservation')[:items].sole
    expect(row).to include(id: "reservation-#{reservation.id}", reason: 'reservation_without_message')
    expect(row[:actions]).to eq(recheck: false, acknowledge: true)
    clear_enqueued_jobs
    service.act(id: row[:id], action: 'acknowledge', version: row[:version])
    expect(reservation.reload).to have_attributes(state: 'review', message_id: nil)
    expect(enqueued_jobs).to be_empty
    expect(service.list(kind: 'reservation', status: 'acknowledged')[:items].size).to eq(1)
  end
end
