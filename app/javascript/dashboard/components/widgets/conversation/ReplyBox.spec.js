import { afterEach, describe, expect, it, vi } from 'vitest';
import ReplyBox from './ReplyBox.vue';

const createContext = overrides => ({
  isFocused: true,
  captainTasksEnabled: true,
  hasMeaningfulEditorContent: true,
  isEditorDisabled: false,
  copilot: {
    isActive: { value: false },
  },
  message: 'Mensagem para revisar',
  executeCopilotAction: vi.fn(),
  ...overrides,
});

describe('ReplyBox Captain shortcuts', () => {
  it.each([
    ['$mod+KeyM', 'improve'],
    ['$mod+KeyO', 'fix_spelling_grammar'],
  ])('maps %s to the %s Captain action', (shortcut, action) => {
    const context = createContext();
    context.handleCaptainShortcut = (event, selectedAction) =>
      ReplyBox.methods.handleCaptainShortcut.call(
        context,
        event,
        selectedAction
      );
    const keyboardEvents = ReplyBox.methods.getKeyboardEvents.call(context);
    const event = { preventDefault: vi.fn(), repeat: false };

    keyboardEvents[shortcut].action(event);

    expect(event.preventDefault).toHaveBeenCalledOnce();
    expect(context.executeCopilotAction).toHaveBeenCalledWith(
      action,
      context.message
    );
  });

  it('intercepts the browser shortcut without calling Captain when unavailable', () => {
    const context = createContext({
      captainTasksEnabled: false,
    });
    const event = { preventDefault: vi.fn(), repeat: false };

    ReplyBox.methods.handleCaptainShortcut.call(context, event, 'improve');

    expect(event.preventDefault).toHaveBeenCalledOnce();
    expect(context.executeCopilotAction).not.toHaveBeenCalled();
  });

  it('adds Captain shortcuts below the existing placeholder', () => {
    const translations = {
      'CONVERSATION.FOOTER.MSG_INPUT': 'Atalhos existentes',
      'CONVERSATION.FOOTER.CAPTAIN_SHORTCUTS':
        'Ctrl + M: melhorar resposta\nCtrl + O: verificar ortografia',
    };
    const context = {
      isEditorDisabled: false,
      isPrivate: false,
      captainTasksEnabled: true,
      $t: key => translations[key],
    };

    expect(ReplyBox.computed.messagePlaceHolder.call(context)).toBe(
      'Atalhos existentes\nCtrl + M: melhorar resposta\nCtrl + O: verificar ortografia'
    );
  });

  it('adds the schedule shortcut only to the WhatsApp reply placeholder', () => {
    const translations = {
      'CONVERSATION.FOOTER.MSG_INPUT': 'Atalhos existentes',
      'CONVERSATION.FOOTER.SCHEDULE_SHORTCUT': 'Ctrl + S: agendar mensagem',
    };
    const context = {
      isEditorDisabled: false,
      isPrivate: false,
      captainTasksEnabled: false,
      inbox: { channel_type: 'Channel::Whatsapp' },
      $t: key => translations[key],
    };

    expect(ReplyBox.computed.messagePlaceHolder.call(context)).toBe(
      'Atalhos existentes\nCtrl + S: agendar mensagem'
    );

    context.isPrivate = true;
    translations['CONVERSATION.FOOTER.PRIVATE_MSG_INPUT'] = 'Nota privada';
    expect(ReplyBox.computed.messagePlaceHolder.call(context)).toBe(
      'Nota privada'
    );
  });
});

describe('ReplyBox compact composer', () => {
  it('queues recorded audio send until its upload finishes', async () => {
    let finishUpload;
    const uploadPromise = new Promise(resolve => {
      finishUpload = resolve;
    });
    const context = {
      recordingAudioState: '',
      hasRecordedAudio: false,
      isRecordedAudioUploadPending: false,
      sendRecordedAudioAfterUpload: false,
      onFileUpload: vi.fn(() => uploadPromise),
      onSendReply: vi.fn(),
    };
    const file = { file: new Blob(['audio'], { type: 'audio/mp3' }) };

    const finishPromise = ReplyBox.methods.onFinishRecorder.call(context, file);
    await ReplyBox.methods.onSendReply.call(context);

    expect(context.sendRecordedAudioAfterUpload).toBe(true);
    expect(context.onSendReply).not.toHaveBeenCalled();

    finishUpload(true);
    await finishPromise;

    expect(context.isRecordedAudioUploadPending).toBe(false);
    expect(context.sendRecordedAudioAfterUpload).toBe(false);
    expect(context.onSendReply).toHaveBeenCalledOnce();
  });

  it('does not focus the message editor automatically on mobile', () => {
    expect(
      ReplyBox.computed.shouldFocusMessageEditorOnMount.call({
        windowWidth: 767,
      })
    ).toBe(false);
  });

  it('keeps automatic focus on tablet and desktop', () => {
    expect(
      ReplyBox.computed.shouldFocusMessageEditorOnMount.call({
        windowWidth: 768,
      })
    ).toBe(true);
  });

  it('uses the compact composer by default for chat inboxes', () => {
    expect(
      ReplyBox.computed.useCompactMessageComposer.call({
        isAnEmailChannel: false,
        accountSettings: {},
      })
    ).toBe(true);
  });

  it('uses the legacy composer when the account enables it', () => {
    expect(
      ReplyBox.computed.useCompactMessageComposer.call({
        isAnEmailChannel: false,
        accountSettings: { use_legacy_message_composer: true },
      })
    ).toBe(false);
  });

  it('always keeps email on the legacy composer', () => {
    expect(
      ReplyBox.computed.useCompactMessageComposer.call({
        isAnEmailChannel: true,
        accountSettings: {},
      })
    ).toBe(false);
  });

  it('uses the compact schedule placeholder for WhatsApp', () => {
    const context = {
      isEditorDisabled: false,
      useCompactMessageComposer: true,
      isPrivate: false,
      inbox: { channel_type: 'Channel::Whatsapp' },
      $t: key => key,
    };

    expect(ReplyBox.computed.messagePlaceHolder.call(context)).toBe(
      'CONVERSATION.REPLYBOX.COMPACT.PLACEHOLDER_WITH_SCHEDULE'
    );
  });
});

describe('ReplyBox direct upload previews', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('uses an object URL instead of reading the whole uploaded file', () => {
    const createObjectURL = vi.fn(() => 'blob:video-preview');
    vi.stubGlobal('URL', {
      createObjectURL,
      revokeObjectURL: vi.fn(),
    });
    const rawFile = { type: 'video/mp4', size: 150 * 1024 * 1024 };
    const context = {
      showFileUpload: true,
      isOnPrivateNote: false,
      enableMultipleFileUpload: true,
      attachedFiles: [],
      currentChat: { id: 42 },
      isPrivate: false,
    };

    ReplyBox.methods.attachFile.call(context, {
      blob: { signed_id: 'signed-blob-id' },
      file: { file: rawFile },
    });

    expect(createObjectURL).toHaveBeenCalledWith(rawFile);
    expect(context.attachedFiles).toEqual([
      expect.objectContaining({
        thumb: 'blob:video-preview',
        previewObjectUrl: 'blob:video-preview',
        blobSignedId: 'signed-blob-id',
      }),
    ]);
  });

  it('releases the preview URL when an attachment is removed', () => {
    const revokeObjectURL = vi.fn();
    vi.stubGlobal('URL', {
      createObjectURL: vi.fn(),
      revokeObjectURL,
    });
    const removedAttachment = { previewObjectUrl: 'blob:removed' };
    const retainedAttachment = { previewObjectUrl: 'blob:retained' };
    const context = {
      attachedFiles: [removedAttachment, retainedAttachment],
      revokeAttachmentPreview: ReplyBox.methods.revokeAttachmentPreview,
    };

    ReplyBox.methods.removeAttachment.call(context, [retainedAttachment]);

    expect(revokeObjectURL).toHaveBeenCalledOnce();
    expect(revokeObjectURL).toHaveBeenCalledWith('blob:removed');
    expect(context.attachedFiles).toEqual([retainedAttachment]);
  });
});
