import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import Action from '../MessageFavoriteAction.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const alert = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alert }));

describe('star message action', () => {
  const load = vi.fn();
  const save = vi.fn();
  const mount = (message = { id: 10, conversation_id: 2 }, favorite = false) =>
    shallowMount(Action, {
      props: { message },
      global: {
        plugins: [
          createStore({
            getters: { 'messageFavorites/isFavorite': () => () => favorite },
            actions: {
              'messageFavorites/load': load,
              'messageFavorites/setFavorite': save,
            },
          }),
        ],
      },
    });
  beforeEach(() => {
    vi.clearAllMocks();
    load.mockResolvedValue();
    save.mockResolvedValue();
  });
  it.each([
    { content: 'Text' },
    { attachments: [{ file_type: 'audio' }] },
    { attachments: [{ file_type: 'image' }] },
  ])('favorites text or attachments: %o', async content => {
    const wrapper = mount({ id: 10, conversation_id: 2, ...content });
    await wrapper.find('button').trigger('click');
    await flushPromises();
    expect(save.mock.calls[0][1]).toEqual({
      conversationId: 2,
      messageId: 10,
      favorite: true,
    });
    expect(wrapper.emitted('close')).toHaveLength(1);
  });
  it('unfavorites a starred message', async () => {
    const wrapper = mount(undefined, true);
    await wrapper.find('button').trigger('click');
    await flushPromises();
    expect(save.mock.calls[0][1].favorite).toBe(false);
  });
  it('keeps the menu open and reports a failed update', async () => {
    save.mockRejectedValue(new Error('offline'));
    const wrapper = mount();
    await wrapper.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.emitted('close')).toBeUndefined();
    expect(alert).toHaveBeenCalledWith('CONVERSATION.FAVORITES.ERROR');
  });
  it('does not offer favorites for unsaved messages', () => {
    expect(mount({ id: 'pending-uuid' }).find('button').exists()).toBe(false);
  });
});
