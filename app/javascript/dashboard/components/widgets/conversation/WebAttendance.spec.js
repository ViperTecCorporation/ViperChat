import { describe, expect, it, vi } from 'vitest';
import ReplyBox from './ReplyBox.vue';
import MessagesView from './MessagesView.vue';

describe('web attendance conversation routing', () => {
  it.each(['unoapi', 'whatsapp_cloud', 'cloud', 'default'])(
    'gates only attendance tabs for %s, regardless of can_reply',
    provider => {
      const context = {
        inbox: {
          channel_type: 'Channel::Whatsapp',
          provider,
          web_attendance_enabled: true,
        },
        currentChat: { group: false, can_reply: false },
      };
      expect(MessagesView.computed.hasWebAttendance.call(context)).toBe(
        ['unoapi', 'whatsapp_cloud'].includes(provider)
      );
      context.currentChat.group = true;
      expect(MessagesView.computed.hasWebAttendance.call(context)).toBe(false);
    }
  );
  it('does not carry a quoted reply across conversations', () => {
    const context = {
      managedDestinations: true,
      inReplyTo: { id: 99 },
      setCCAndToEmailsFromLastChat: vi.fn(),
      copilot: { reset: vi.fn() },
    };
    ReplyBox.watch.currentChat.call(context, { id: 2 }, { id: 1 });
    expect(context.inReplyTo).toEqual({});
  });
  it('marks only the visible destination and never calls generic read', () => {
    const context = {
      hasWebAttendance: true,
      deliveryDestination: 'web',
      markAttendanceSeen: vi.fn().mockResolvedValue(),
      $store: { dispatch: vi.fn() },
      currentChat: { id: 42 },
    };
    MessagesView.methods.makeMessagesRead.call(context);
    expect(context.markAttendanceSeen).toHaveBeenCalledWith('web');
    expect(context.$store.dispatch).not.toHaveBeenCalled();
  });

  it('preserves generic reads for inboxes without the feature', () => {
    const context = {
      hasWebAttendance: false,
      $store: { dispatch: vi.fn() },
      currentChat: { id: 42 },
    };
    MessagesView.methods.makeMessagesRead.call(context);
    expect(context.$store.dispatch).toHaveBeenCalledWith('markMessagesRead', {
      id: 42,
    });
  });

  it('uses the selected destination unread counter', () => {
    expect(
      MessagesView.computed.unreadMessageCount.call({
        hasWebAttendance: true,
        deliveryDestination: 'web',
        attendance: { unread: { channel: 8, web: 2 } },
        currentChat: { unread_count: 10 },
      })
    ).toBe(2);
  });

  it('keeps attachment, audio and contact composer state when switching to notes', () => {
    const attachedFiles = [{ blobSignedId: 'blob', isRecordedAudio: true }];
    const attachedContacts = [{ name: 'Contact' }];
    const context = {
      managedDestinations: true,
      attachedFiles,
      attachedContacts,
      $emit: vi.fn(),
      clearAttachedFiles: vi.fn(),
    };
    ReplyBox.methods.setReplyMode.call(context, 'NOTE');
    expect(context.$emit).toHaveBeenCalledWith('setReplyMode', 'NOTE');
    expect(context.clearAttachedFiles).not.toHaveBeenCalled();
    expect(context.attachedFiles).toBe(attachedFiles);
    expect(context.attachedContacts).toBe(attachedContacts);
  });

  it.each([false, true])(
    'routes a web public reply/private note %s correctly',
    async isPrivate => {
      const context = {
        deliveryDestination: 'web',
        $store: { dispatch: vi.fn().mockResolvedValue() },
        removeFromDraft: vi.fn(),
        sendMessageAnalyticsData: vi.fn(),
      };
      await ReplyBox.methods.sendMessage.call(context, {
        conversationId: 42,
        private: isPrivate,
        contentAttributes: { contacts: [{ name: 'Contact' }] },
      });
      expect(context.$store.dispatch).toHaveBeenCalledWith(
        'createPendingMessageAndSend',
        expect.objectContaining({
          delivery_destination: isPrivate ? 'channel' : 'web',
        })
      );
    }
  );

  it('ignores paste and native share in a hidden composer', () => {
    const context = { isComposerActive: false, addIntoEditor: vi.fn() };
    ReplyBox.methods.onPaste.call(context, {});
    ReplyBox.methods.onNativeShareReceived.call(context, { text: 'shared' });
    expect(context.addIntoEditor).not.toHaveBeenCalled();
  });

  it.each(['image/jpeg', 'video/mp4', 'audio/ogg', 'application/pdf'])(
    'routes %s attachments to Web without changing their payload',
    async type => {
      const file = new File(['media'], 'attachment', { type });
      const payload = {
        conversationId: 42,
        private: false,
        files: [file],
        contentAttributes: { in_reply_to: 99, view_once: true },
      };
      const context = {
        deliveryDestination: 'web',
        $store: { dispatch: vi.fn().mockResolvedValue() },
        removeFromDraft: vi.fn(),
        sendMessageAnalyticsData: vi.fn(),
      };
      await ReplyBox.methods.sendMessage.call(context, payload);
      expect(context.$store.dispatch).toHaveBeenCalledWith(
        'createPendingMessageAndSend',
        { ...payload, delivery_destination: 'web' }
      );
      expect(payload).not.toHaveProperty('delivery_destination');
    }
  );

  it('does not send a hidden composer or a revoked Web session', async () => {
    const context = { isComposerActive: false, confirmOnSendReply: vi.fn() };
    await ReplyBox.methods.onSendReply.call(context);
    context.isComposerActive = true;
    context.isEditorDisabled = true;
    await ReplyBox.methods.onSendReply.call(context);
    expect(context.confirmOnSendReply).not.toHaveBeenCalled();
  });

  it('enables web replies independently from the WhatsApp reply window', () => {
    expect(
      ReplyBox.computed.isEditorDisabled.call({
        isComposerActive: true,
        isWebDestination: true,
        isOnPrivateNote: false,
        webAttendanceActive: true,
        currentChat: { can_reply: false },
      })
    ).toBe(false);
  });

  it('disables web replies after revocation', () => {
    expect(
      ReplyBox.computed.isEditorDisabled.call({
        isComposerActive: true,
        isWebDestination: true,
        isOnPrivateNote: false,
        webAttendanceActive: false,
      })
    ).toBe(true);
  });
});
