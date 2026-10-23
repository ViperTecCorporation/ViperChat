require 'rails_helper'

RSpec.describe Voip::PublishCallArtifactService do
  let(:account) { create(:account) }
  let(:service) do
    VoipService.create!(account: account, name: 'Central', wss_url: 'wss://sip.example.test/ws', sip_domain: 'sip.example.test',
                        credentials: { integration_provider: 'webhook', webhook_source_instance_id: 'pbx-1' })
  end
  let(:channel) do
    create(:channel_whatsapp, account: account, phone_number: '+5566996222471', provider: 'unoapi',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:contact) { create(:contact, account: account, phone_number: '+5566999999999') }
  let!(:conversation) { create(:conversation, account: account, inbox: channel.inbox, contact: contact, status: :resolved) }
  let(:external) { VoipExternalCall.create!(voip_service: service, source_instance_id: 'pbx-1', provider_call_id: 'call-1') }
  let(:snapshot) do
    { 'ai' => { 'status' => 'completed', 'summary' => 'Resumo seguro', 'transcript' => "Olá\nTeste" },
      'note_target' => { 'business_phone' => '5566996222471', 'remote_phone' => '5566999999999' } }
  end
  let(:artifact) { external.create_voip_call_artifact!(snapshot: snapshot, desired_revision: 1) }

  it 'updates one private note without reopening the existing conversation or changing historical identities' do
    described_class.new(artifact: artifact).perform
    note = artifact.reload.message
    expect([note.private?, note.outgoing?]).to eq([true, true])
    expect(note.content).to include('Resumo seguro', "Olá\nTeste")
    expect(conversation.reload).to be_resolved
    original_ids = [note.id, conversation.id, contact.id]
    contact.update!(phone_number: '+5566988888888')
    artifact.update!(desired_revision: 2, state: 'pending', snapshot: snapshot.deep_merge('ai' => { 'summary' => 'Resumo corrigido' }))
    expect { described_class.new(artifact: artifact).perform }.not_to change(Message, :count)
    expect([artifact.reload.message_id, artifact.conversation_id, artifact.conversation.contact_id]).to eq(original_ids)
    expect(note.reload.content).to include('Resumo corrigido')
    expect(conversation.reload).to be_resolved
  end

  it 'keeps unmatched artifacts in history without creating contacts, conversations or notes' do
    snapshot['note_target']['remote_phone'] = '5511999999999'
    artifact
    expect { described_class.new(artifact: artifact).perform }.not_to change(Message, :count)
    expect(artifact.reload.state).to eq('pending_conversation')
    expect(artifact.message_id).to be_nil
    expect(account.conversations.count).to eq(1)
    expect(account.contacts.count).to eq(1)
  end

  it 'refuses ambiguous phone evidence and never chooses a contact by name' do
    other = create(:contact, account: account, phone_number: '+5511999999999', name: contact.name)
    create(:contact_inbox, inbox: channel.inbox, contact: other, source_id: '5566999999999')
    described_class.new(artifact: artifact).perform
    expect(artifact.reload.state).to eq('ambiguous')
    expect(artifact.message_id).to be_nil
  end

  it 'does not choose the latest conversation when several existing conversations match' do
    create(:conversation, account: account, inbox: channel.inbox, contact: contact)
    expect { described_class.new(artifact: artifact).perform }.not_to change(Message, :count)
    expect(artifact.reload.state).to eq('ambiguous')
    expect(artifact.conversation_id).to be_nil
  end

  it 'persists a retry after download failure even after the provider event has been processed' do
    snapshot['recording'] = { 'status' => 'available', 'record_id' => 'record-1' }
    client = instance_double(Voip::RecordingClient)
    allow(Voip::RecordingClient).to receive(:new).with(service).and_return(client)
    allow(client).to receive(:fetch).and_raise(Voip::ServiceHistoryClient::ResponseError)
    described_class.new(artifact: artifact).perform
    expect(artifact.reload.state).to eq('retry')
    expect(artifact.attempts).to eq(1)
    expect(artifact.next_attempt_at).to be > Time.current
    expect(artifact.message_id).to be_nil
  end

  it 'attaches an authenticated recording once and reuses its blob in the note' do
    snapshot['recording'] = { 'status' => 'available', 'record_id' => 'record-1' }
    file = Tempfile.new(['voip-test', '.wav'])
    file.binmode
    file.write("RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x40\x1f\x00\x00\x80\x3e\x00\x00\x02\x00\x10\x00data\x00\x00\x00\x00")
    file.rewind
    client = instance_double(Voip::RecordingClient, fetch: { file: file, mime: 'audio/wav', digest: 'a' * 64 })
    allow(Voip::RecordingClient).to receive(:new).with(service).and_return(client)
    described_class.new(artifact: artifact).perform
    expect(artifact.reload.recording).to be_attached
    expect(artifact.message.attachments.sole.file.blob_id).to eq(artifact.recording.blob.id)
    expect { described_class.new(artifact: artifact).perform }.not_to change(Attachment, :count)
    expect(client).to have_received(:fetch).once
  ensure
    file&.close!
  end
end
