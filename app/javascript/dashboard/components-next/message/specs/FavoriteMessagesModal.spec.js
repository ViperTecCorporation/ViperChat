import { mount, flushPromises } from '@vue/test-utils';
import { defineComponent } from 'vue';
import { createStore } from 'vuex';
import Modal from '../FavoriteMessagesModal.vue';
import api from 'dashboard/api/messageFavorites';

const push = vi.hoisted(() => vi.fn());
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: { value: 'pt_BR' } }),
}));
vi.mock('dashboard/api/messageFavorites', () => ({
  default: { list: vi.fn() },
}));
vi.mock('shared/composables/useMessageFormatter', () => ({
  useMessageFormatter: () => ({ getPlainText: value => value }),
}));
const Dialog = defineComponent({
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template: '<div><slot /></div>',
});
const Button = { props: ['label'], template: '<button>{{ label }}</button>' };
const row = {
  id: 7,
  contact_name: 'Contato',
  inbox_name: 'WhatsApp',
  message: {
    id: 123,
    conversation_id: 42,
    content: 'Favorita',
    created_at: 100,
  },
};
describe('favorite messages modal', () => {
  const navigate = vi.fn();
  const remove = vi.fn();
  const open = async () => {
    const wrapper = mount(Modal, {
      props: { contactId: 9 },
      global: {
        plugins: [
          createStore({
            getters: { getCurrentAccountId: () => 1 },
            actions: {
              loadFavoriteMessage: navigate,
              'messageFavorites/setFavorite': remove,
            },
          }),
        ],
        stubs: { Dialog, Button, Avatar: true, Icon: true },
      },
    });
    wrapper.vm.open();
    await flushPromises();
    return wrapper;
  };
  beforeEach(() => {
    vi.clearAllMocks();
    api.list.mockResolvedValue({ data: { payload: [row], has_more: false } });
    navigate.mockResolvedValue();
    remove.mockResolvedValue();
  });
  it('loads favorites for the contact and navigates to the original bubble', async () => {
    const wrapper = await open();
    expect(api.list).toHaveBeenCalledWith(
      expect.objectContaining({ contact_id: 9 })
    );
    expect(wrapper.text()).toContain('Favorita');
    await wrapper
      .find('[aria-label="CONVERSATION.FAVORITES.GO_TO_MESSAGE"]')
      .trigger('click');
    await flushPromises();
    expect(navigate.mock.calls[0][1]).toEqual({
      conversationId: 42,
      messageId: 123,
    });
    expect(push).toHaveBeenCalledWith(
      expect.objectContaining({ query: { messageId: 123 } })
    );
  });
  it('does not navigate if original message is inaccessible', async () => {
    navigate.mockRejectedValue(new Error('403'));
    const wrapper = await open();
    await wrapper
      .find('[aria-label="CONVERSATION.FAVORITES.GO_TO_MESSAGE"]')
      .trigger('click');
    await flushPromises();
    expect(push).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('CONVERSATION.FAVORITES.UNAVAILABLE');
  });
  it('removes a favorite without deleting the original message', async () => {
    const wrapper = await open();
    await wrapper
      .find('[aria-label="CONVERSATION.FAVORITES.REMOVE"]')
      .trigger('click');
    await flushPromises();
    expect(remove.mock.calls[0][1]).toEqual({
      conversationId: 42,
      messageId: 123,
      favorite: false,
    });
    expect(wrapper.find('article').exists()).toBe(false);
  });
  it('shows an error when loading fails', async () => {
    api.list.mockRejectedValue(new Error('offline'));
    expect((await open()).text()).toContain('CONVERSATION.FAVORITES.ERROR');
  });
  it('paginates using the last favorite id', async () => {
    api.list.mockResolvedValueOnce({
      data: { payload: [row], has_more: true },
    });
    const wrapper = await open();
    api.list.mockResolvedValueOnce({ data: { payload: [], has_more: false } });
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'CONVERSATION.FAVORITES.MORE')
      .trigger('click');
    await flushPromises();
    expect(api.list).toHaveBeenLastCalledWith(
      expect.objectContaining({ before: 7 })
    );
  });
});
