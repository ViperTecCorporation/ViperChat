import { describe, expect, it, vi } from 'vitest';
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
