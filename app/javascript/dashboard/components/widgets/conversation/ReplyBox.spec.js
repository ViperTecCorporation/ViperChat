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
});
