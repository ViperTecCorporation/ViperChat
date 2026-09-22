import { mount, flushPromises } from '@vue/test-utils';
import { defineComponent } from 'vue';
import Archived from '../ArchivedConversations.vue';
import api from 'dashboard/api/conversations';

const restore = vi.hoisted(() => vi.fn());
const push = vi.hoisted(() => vi.fn());
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: { getCurrentAccountId: 1 } }),
}));
vi.mock('dashboard/api/conversations', () => ({
  default: { getArchived: vi.fn() },
}));
vi.mock('dashboard/composables/useConversationArchives', () => ({
  useConversationArchives: () => ({ archives: [7], setArchived: restore }),
}));
const Dialog = defineComponent({
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template: '<div><slot /></div>',
});
const row = { id: 7, messages: [], meta: { sender: { name: 'Contato' } } };
describe('archived conversations', () => {
  const open = async () => {
    const wrapper = mount(Archived, {
      global: {
        stubs: {
          Dialog,
          Avatar: true,
          Button: { props: ['label'], template: '<button>{{label}}</button>' },
        },
      },
    });
    await wrapper.find('button').trigger('click');
    await flushPromises();
    return wrapper;
  };
  beforeEach(() => {
    vi.clearAllMocks();
    restore.mockResolvedValue();
    api.getArchived.mockResolvedValue({
      data: { payload: [row], has_more: false },
    });
  });
  it('lists and opens an archived conversation without restoring it', async () => {
    const wrapper = await open();
    await wrapper.find('article button').trigger('click');
    expect(push).toHaveBeenCalledWith(
      expect.objectContaining({ params: { accountId: 1, conversation_id: 7 } })
    );
    expect(restore).not.toHaveBeenCalled();
  });
  it('restores and reloads the list', async () => {
    const wrapper = await open();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'CONVERSATION.ARCHIVE.RESTORE')
      .trigger('click');
    await flushPromises();
    expect(restore).toHaveBeenCalledWith(7, false);
    expect(api.getArchived).toHaveBeenCalledTimes(2);
  });
  it.each([
    [
      { content: 'Última mensagem de texto', message_type: 0 },
      'Última mensagem de texto',
    ],
    [
      {
        content: null,
        attachments: [
          { file_type: 'audio', transcribed_text: 'Áudio transcrito' },
        ],
      },
      'Áudio transcrito',
    ],
  ])('renders the conversation preview for %j', async (message, expected) => {
    api.getArchived.mockResolvedValue({
      data: { payload: [{ ...row, messages: [message] }], has_more: false },
    });
    expect((await open()).find('article').text()).toContain(expected);
  });
  it('reports an unavailable server', async () => {
    api.getArchived.mockRejectedValue(new Error('offline'));
    expect((await open()).find('[role="alert"]').exists()).toBe(true);
  });
  it('loads the next page', async () => {
    api.getArchived.mockResolvedValueOnce({
      data: { payload: [row], has_more: true },
    });
    const wrapper = await open();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'CONVERSATION.ARCHIVE.MORE')
      .trigger('click');
    await flushPromises();
    expect(api.getArchived).toHaveBeenLastCalledWith(2);
  });
});
