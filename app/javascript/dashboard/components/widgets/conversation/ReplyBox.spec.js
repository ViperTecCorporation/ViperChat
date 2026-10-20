import { afterEach, describe, expect, it, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import ReplyBox from './ReplyBox.vue';
import replyBoxSource from './ReplyBox.vue?raw';
import { useAlert } from 'dashboard/composables';
import { compile, ref } from 'vue';
import { useWhatsappTransport } from 'dashboard/composables/useWhatsappTransport';
import scheduledMessagesApi from 'dashboard/api/scheduledMessages';
import mediaEditorMixin from 'dashboard/mixins/mediaEditorMixin';

vi.mock('dashboard/api/scheduledMessages', () => ({
  default: { create: vi.fn() },
}));

vi.mock('dashboard/composables', async importOriginal => ({
  ...(await importOriginal()),
  useAlert: vi.fn(),
}));

describe('ReplyBox unified WhatsApp composer', () => {
  it.each(
    [true, false].flatMap(compact =>
      ['unoapi', 'whatsapp_cloud', undefined].flatMap(provider =>
        ['image/jpeg', 'video/mp4'].map(type => ({ compact, provider, type }))
      )
    )
  )(
    'opens edited media through the actual ReplyBox handler: %j',
    async ({ compact, provider, type }) => {
      const onIndirectFileUpload = vi.fn();
      const wrapper = mount({
        mixins: [mediaEditorMixin],
        data: () => ({
          useCompactMessageComposer: compact,
          selectedWhatsappProvider: provider,
          whatsappTransportOptions: provider ? { link_id: 1 } : null,
          transportUploadCount: 0,
          currentChat: { id: 9 },
          accountId: 1,
          isAUnoapiChannel: true,
          isPrivate: false,
          isOnPrivateNote: false,
          isEditorDisabled: false,
          isReplyRestricted: false,
          showFileUpload: true,
          attachedFiles: [],
          attachedContacts: [],
          message: 'Caption',
          inReplyTo: { id: 123 },
          globalConfig: { directUploadsEnabled: false },
        }),
        methods: {
          onFileUpload: ReplyBox.methods.onFileUpload,
          onIndirectFileUpload,
        },
        template:
          '<div><div v-if="mediaEditorSession" data-test="media-editor" /></div>',
      });
      const media = new File(['media'], 'media', { type });
      await wrapper.vm.onFileUpload({ file: media });
      expect(wrapper.find('[data-test="media-editor"]').exists()).toBe(true);
      expect(wrapper.vm.mediaEditorFiles).toEqual([media]);
      expect(wrapper.vm.mediaEditorSession.whatsappProvider).toBe(provider);
      expect(wrapper.vm.transportUploadCount).toBe(0);
      expect(onIndirectFileUpload).not.toHaveBeenCalled();
      expect(ReplyBox.computed.isTransportSwitchDisabled.call(wrapper.vm)).toBe(
        true
      );
      expect(wrapper.vm.selectedWhatsappProvider).toBe(provider);
      wrapper.unmount();
    }
  );

  it.each(['application/pdf', 'audio/ogg', 'image/jpeg'])(
    'keeps ordinary attachments and private-note images on the upload path: %s',
    async type => {
      const context = {
        ...mediaEditorMixin.data(),
        transportUploadCount: 0,
        isPrivate: type === 'image/jpeg',
        isEditorDisabled: false,
        showFileUpload: true,
        attachedFiles: [],
        attachedContacts: [],
        isAUnoapiChannel: true,
        globalConfig: { directUploadsEnabled: false },
        onIndirectFileUpload: vi.fn().mockResolvedValue(true),
      };
      const item = { file: new File(['data'], 'attachment', { type }) };
      await ReplyBox.methods.onFileUpload.call(context, item);
      expect(context.onIndirectFileUpload).toHaveBeenCalledWith(item);
      expect(context.mediaEditorSession).toBeNull();
      expect(context.transportUploadCount).toBe(0);
    }
  );

  it('unlocks transport selection after an ordinary upload fails', async () => {
    const context = {
      ...mediaEditorMixin.data(),
      transportUploadCount: 0,
      isPrivate: true,
      globalConfig: { directUploadsEnabled: false },
      onIndirectFileUpload: vi
        .fn()
        .mockRejectedValue(new Error('Upload failed')),
    };
    await expect(
      ReplyBox.methods.onFileUpload.call(context, {
        file: new File(['data'], 'file.pdf', { type: 'application/pdf' }),
      })
    ).rejects.toThrow('Upload failed');
    expect(context.transportUploadCount).toBe(0);
  });

  it('allows the scheduling shortcut for a linked inbox despite the current Meta reply restriction', () => {
    const context = {
      isComposerActive: true,
      isWebDestination: false,
      inbox: { channel_type: 'Channel::Whatsapp' },
      whatsappTransportOptions: { link_id: 1 },
      isReplyButtonDisabled: true,
      isTransportSwitchDisabled: false,
      openScheduleModal: vi.fn(),
    };
    ReplyBox.methods.handleScheduleShortcut.call(context, {
      ctrlKey: true,
      key: 's',
      preventDefault: vi.fn(),
    });
    expect(context.openScheduleModal).toHaveBeenCalledOnce();
    context.whatsappTransportOptions = null;
    context.openScheduleModal.mockClear();
    ReplyBox.methods.handleScheduleShortcut.call(context, {
      ctrlKey: true,
      key: 's',
      preventDefault: vi.fn(),
    });
    expect(context.openScheduleModal).not.toHaveBeenCalled();
  });
  it.each([true, false])(
    'freezes scheduling independently of compact=%s',
    compact => {
      const context = {
        useCompactMessageComposer: compact,
        isWebDestination: false,
        whatsappTransportOptions: { link_id: 1 },
        selectedWhatsappProvider: 'whatsapp_cloud',
        currentUser: { id: 3 },
        message: 'Scheduled draft',
        attachedFiles: [],
        toDatetimeLocal: date => date.toISOString(),
      };
      ReplyBox.methods.openScheduleModal.call(context);
      expect(context.showScheduleModal).toBe(true);
      expect(context.scheduledWhatsappProvider).toBe('whatsapp_cloud');
      context.selectedWhatsappProvider = 'unoapi';
      expect(context.scheduledWhatsappProvider).toBe('whatsapp_cloud');
      context.scheduledWhatsappProvider = 'whatsapp_cloud';
      expect(context.selectedWhatsappProvider).toBe('unoapi');
    }
  );

  it.each([true, false])(
    'serializes only a provider string when linked=%s',
    async linked => {
      scheduledMessagesApi.create.mockResolvedValue({ data: {} });
      const context = {
        whatsappTransportOptions: linked ? { link_id: 1 } : null,
        scheduledWhatsappProvider: 'whatsapp_cloud',
        scheduledLabelId: 2,
        scheduledAt: '2030-10-20T12:00',
        scheduledSenderId: 3,
        scheduledItems: [{ content: 'Later', attachments: [] }],
        isScheduleValid: true,
        currentChat: { id: 4 },
        clearMessage: vi.fn(),
      };
      await ReplyBox.methods.createScheduledMessage.call(context);
      const payload = scheduledMessagesApi.create.mock.calls[0][0];
      if (linked)
        expect(payload.scheduled_message.whatsapp_transport).toBe(
          'whatsapp_cloud'
        );
      else
        expect(payload.scheduled_message).not.toHaveProperty(
          'whatsapp_transport'
        );
      expect(payload.conversation_id).toBe(4);
    }
  );

  it('keeps the scheduling dialog and draft on a 422 transport error', async () => {
    scheduledMessagesApi.create.mockRejectedValue({
      response: { status: 422, data: { errors: ['Transport link changed'] } },
    });
    const context = {
      scheduledLabelId: 2,
      scheduledAt: '2030-10-20T12:00',
      scheduledItems: [{ content: 'Keep draft', attachments: [] }],
      isScheduleValid: true,
      showScheduleModal: true,
      currentChat: { id: 4 },
      clearMessage: vi.fn(),
    };
    await ReplyBox.methods.createScheduledMessage.call(context);
    expect(useAlert).toHaveBeenCalledWith('Transport link changed');
    expect(context.clearMessage).not.toHaveBeenCalled();
    expect(context.showScheduleModal).toBe(true);
  });

  it('preserves the unlinked audio recording format and uses the scheduled provider for linked audio', () => {
    expect(
      ReplyBox.computed.scheduleAudioRecordFormat.call({
        audioRecordFormat: 'wav',
      })
    ).toBe('wav');
    expect(
      ReplyBox.computed.scheduleAudioRecordFormat.call({
        whatsappTransportOptions: {},
        scheduledWhatsappProvider: 'whatsapp_cloud',
      })
    ).toBe('audio/ogg');
    expect(
      ReplyBox.computed.scheduleAudioRecordFormat.call({
        whatsappTransportOptions: {},
        scheduledWhatsappProvider: 'unoapi',
      })
    ).toBe('audio/mp3');
  });

  it.each([true, false])(
    'preserves per-provider text, files and quote when compact=%s and switching layouts',
    compact => {
      const chat = ref({
        id: `draft-${compact}`,
        account_id: 53,
        whatsapp_transport_options: {
          link_id: 11,
          default_provider: 'unoapi',
          transports: [
            { provider: 'unoapi', inbox_id: 1, can_reply: true },
            { provider: 'whatsapp_cloud', inbox_id: 2, can_reply: true },
          ],
        },
      });
      const transport = useWhatsappTransport(chat, 42);
      const saved = {};
      const context = {
        useCompactMessageComposer: compact,
        whatsappTransport: transport,
        whatsappTransportOptions: chat.value.whatsapp_transport_options,
        conversationIdByRoute: chat.value.id,
        replyType: 'REPLY',
        deliveryDestination: 'channel',
        isWebDestination: false,
        isTransportSwitchDisabled: false,
        message: 'ViperConnect draft',
        attachedFiles: [
          {
            blobSignedId: 'existing-upload',
            previewObjectUrl: 'blob:existing',
          },
        ],
        attachedContacts: [{ id: 9 }],
        inReplyTo: { id: 32 },
        transportDrafts: {},
        maxLength: 4096,
        $store: {
          dispatch: vi.fn((action, { key, message }) => {
            saved[key] = message;
          }),
          getters: { 'draftMessages/get': key => saved[key] },
        },
        toggleSignatureForDraft: message => message,
      };
      Object.defineProperty(context, 'selectedWhatsappProvider', {
        get: () => transport.selectedProvider.value,
      });
      ['getDraftKey', 'saveDraft', 'getFromDraft'].forEach(method => {
        context[method] = ReplyBox.methods[method].bind(context);
      });
      ReplyBox.methods.selectWhatsappTransport.call(context, 'whatsapp_cloud');
      expect(context.message).toBe('');
      expect(context.attachedFiles).toEqual([]);
      expect(context.inReplyTo).toEqual({});
      context.message = 'Meta draft';
      context.attachedFiles = [{ blobSignedId: 'meta-upload' }];
      context.inReplyTo = { id: 33 };
      context.useCompactMessageComposer = !compact;
      expect(context.selectedWhatsappProvider).toBe('whatsapp_cloud');
      ReplyBox.methods.selectWhatsappTransport.call(context, 'unoapi');
      expect(context.message).toBe('ViperConnect draft');
      expect(context.attachedFiles[0].blobSignedId).toBe('existing-upload');
      expect(context.inReplyTo).toEqual({ id: 32 });
      ReplyBox.methods.selectWhatsappTransport.call(context, 'whatsapp_cloud');
      expect(context.message).toBe('Meta draft');
      expect(context.attachedFiles[0].blobSignedId).toBe('meta-upload');
      expect(context.inReplyTo).toEqual({ id: 33 });
      expect(
        context.$store.dispatch.mock.calls.every(
          ([action]) => action === 'draftMessages/set'
        )
      ).toBe(true);
    }
  );

  it('reports backend capability routing without changing selected transport', async () => {
    const context = {
      whatsappTransportOptions: {
        transports: [{ provider: 'unoapi', label: 'ViperConnect' }],
      },
      selectedWhatsappProvider: 'whatsapp_cloud',
      deliveryDestination: 'channel',
      $store: {
        dispatch: vi.fn().mockResolvedValue({
          content_attributes: {
            whatsapp_transport: {
              requested_provider: 'whatsapp_cloud',
              provider: 'unoapi',
              reason: 'capability_routing',
            },
          },
        }),
      },
      $t: (key, params) => `${key}:${params?.provider || ''}`,
      removeFromDraft: vi.fn(),
      sendMessageAnalyticsData: vi.fn(),
    };
    await ReplyBox.methods.sendMessage.call(context, {
      conversationId: 1,
      message: 'Hello',
      private: false,
    });
    expect(context.$store.dispatch).toHaveBeenCalledWith(
      'createPendingMessageAndSend',
      expect.objectContaining({ whatsapp_transport: 'whatsapp_cloud' })
    );
    expect(useAlert).toHaveBeenCalledWith(
      'WHATSAPP_UNIFIED.ROUTED:ViperConnect'
    );
    expect(context.selectedWhatsappProvider).toBe('whatsapp_cloud');
  });
});

describe('ReplyBox contact validation', () => {
  it('warns before sending and preserves the selected contacts', () => {
    const attachedContacts = [
      { name: 'Incomplete', phone_number: '', email: '' },
    ];
    const context = {
      attachedContacts,
      serializeAttachedContact: ReplyBox.methods.serializeAttachedContact,
      $t: (key, values) => `${key}: ${values?.name || ''}`,
      sendMessageAsMultipleMessages: vi.fn(),
    };
    ReplyBox.methods.confirmOnSendReply.call(context);
    expect(useAlert).toHaveBeenCalledWith(
      expect.stringContaining('Incomplete')
    );
    expect(context.sendMessageAsMultipleMessages).not.toHaveBeenCalled();
    expect(context.attachedContacts).toBe(attachedContacts);
  });

  it('keeps multiple valid contacts in a single outgoing payload', () => {
    const context = {
      attachedContacts: [
        { name: 'First', phone_number: '+15555550101' },
        { name: 'Second', email: 'second@example.com' },
      ],
      attachedFiles: [],
      currentChat: { id: 1 },
      sender: { id: 1 },
      serializeAttachedContact: ReplyBox.methods.serializeAttachedContact,
      setReplyToInPayload: payload => payload,
      withGroupMentionsInPayload: payload => payload,
    };
    const messages = ReplyBox.methods.getMultipleMessagesPayload.call(
      context,
      ''
    );
    expect(messages).toHaveLength(1);
    expect(messages[0].contentAttributes.contacts).toHaveLength(2);
  });
});

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
  it.each([true, false])(
    'shows the standalone schedule button only outside compact mode (compact=%s)',
    async compact => {
      // Render the production button fragment without mounting the editor's
      // unrelated stores, uploads and websocket subscriptions.
      const fragment = [...replyBoxSource.matchAll(/<NextButton\b[\s\S]*?\/>/g)]
        .map(match => match[0])
        .find(template => template.includes('WHATSAPP_UNIFIED.SCHEDULE.OPEN'));
      const openScheduleModal = vi.fn();
      const wrapper = mount(
        {
          render: compile(fragment),
          data: () => ({
            useCompactMessageComposer: compact,
            isComposerActive: true,
            isTransportSwitchDisabled: false,
          }),
          methods: { openScheduleModal },
        },
        {
          global: {
            mocks: { $t: key => key },
            stubs: {
              NextButton: {
                props: ['label'],
                template: '<button>{{ label }}</button>',
              },
            },
          },
        }
      );
      expect(wrapper.find('button').exists()).toBe(!compact);
      if (!compact) {
        await wrapper.get('button').trigger('click');
        expect(openScheduleModal).toHaveBeenCalledOnce();
      }
      wrapper.unmount();
    }
  );

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

describe('ReplyBox view-once audio', () => {
  it.each([true, false])(
    'marks only recorded audio when selected: %s',
    selected => {
      const context = {
        isAUnoapiChannel: true,
        recordedAudioViewOnce: selected,
        attachedContacts: [],
        attachedFiles: [
          { isRecordedAudio: true, blobSignedId: 'audio-blob' },
          { blobSignedId: 'document-blob' },
        ],
        currentChat: { id: 9 },
        sender: { id: 7 },
        setReplyToInPayload: payload => ({
          ...payload,
          contentAttributes: { in_reply_to: 42 },
        }),
        withGroupMentionsInPayload: payload => payload,
      };
      const messages = ReplyBox.methods.getMultipleMessagesPayload.call(
        context,
        ''
      );
      expect(messages[0].contentAttributes).toEqual({
        in_reply_to: 42,
        ...(selected ? { view_once: true } : {}),
      });
      expect(messages[1].contentAttributes).toEqual({ in_reply_to: 42 });
    }
  );

  it('clears the selection when resetting the recorder', () => {
    const context = {
      recordedAudioViewOnce: true,
      attachedFiles: [],
      revokeAttachmentPreview: vi.fn(),
    };
    ReplyBox.methods.resetAudioRecorderInput.call(context);
    expect(context.recordedAudioViewOnce).toBe(false);
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
