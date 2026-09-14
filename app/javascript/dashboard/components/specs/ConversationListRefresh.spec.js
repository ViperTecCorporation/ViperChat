import { shallowMount } from '@vue/test-utils';
import ConversationList from '../ConversationList.vue';
import { emitter } from 'shared/helpers/mitt';

vi.mock('dashboard/composables/chatlist/useChatListKeyboardEvents', () => ({
  useChatListKeyboardEvents: vi.fn(),
}));
vi.mock('shared/helpers/mitt', () => ({ emitter: { emit: vi.fn() } }));

describe('conversation list pull refresh', () => {
  beforeEach(() => vi.clearAllMocks());

  it('refreshes on an upward pull at the end of the list', async () => {
    const wrapper = shallowMount(ConversationList);
    Object.defineProperties(wrapper.element, {
      scrollTop: { value: 400 },
      clientHeight: { value: 100 },
      scrollHeight: { value: 500 },
    });
    await wrapper.trigger('touchstart', {
      touches: [{ clientX: 100, clientY: 250 }],
    });
    await wrapper.trigger('touchmove', {
      touches: [{ clientX: 100, clientY: 100 }],
    });
    await wrapper.trigger('touchend');
    expect(emitter.emit).toHaveBeenCalledWith('refresh_conversation_list');
    wrapper.unmount();
  });

  it('does not refresh during normal scrolling', async () => {
    const wrapper = shallowMount(ConversationList);
    Object.defineProperties(wrapper.element, {
      scrollTop: { value: 100 },
      clientHeight: { value: 100 },
      scrollHeight: { value: 500 },
    });
    await wrapper.trigger('touchstart', {
      touches: [{ clientX: 100, clientY: 250 }],
    });
    await wrapper.trigger('touchmove', {
      touches: [{ clientX: 100, clientY: 100 }],
    });
    await wrapper.trigger('touchend');
    expect(emitter.emit).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});
