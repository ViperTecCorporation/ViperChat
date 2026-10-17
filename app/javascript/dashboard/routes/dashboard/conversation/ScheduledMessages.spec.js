import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import ScheduledMessages from './ScheduledMessages.vue';
import scheduledMessagesApi from 'dashboard/api/scheduledMessages';
import ConversationsAPI from 'dashboard/api/conversations';
import { useAlert } from 'dashboard/composables';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/api/scheduledMessages', () => ({
  default: { getForRange: vi.fn(), create: vi.fn(), update: vi.fn() },
}));
vi.mock('dashboard/api/conversations', () => ({ default: { show: vi.fn() } }));
vi.mock('dashboard/composables', async importOriginal => ({
  ...(await importOriginal()),
  useAlert: vi.fn(),
}));

const options = {
  link_id: 3,
  default_provider: 'whatsapp_cloud',
  transports: [
    { provider: 'unoapi' },
    { provider: 'whatsapp_cloud', can_reply: false },
  ],
};
const schedule = {
  id: 4,
  scheduled_at: '2030-10-20T12:00:00Z',
  label: { id: 5 },
  sender: { id: 6 },
  inbox: { id: 7 },
  messages: [{ content: 'Later', attachments: [] }],
};
let wrapper;
beforeEach(() => {
  scheduledMessagesApi.getForRange.mockResolvedValue({ data: [] });
  scheduledMessagesApi.update.mockResolvedValue({ data: {} });
  scheduledMessagesApi.create.mockResolvedValue({ data: {} });
  const store = createStore({
    getters: {
      getCurrentUser: () => ({
        id: 6,
        accounts: [{ id: 1, role: 'administrator' }],
      }),
      'inboxes/getInboxes': () => [{ id: 7, provider: 'unoapi' }],
      'agents/getAgents': () => [],
      'labels/getLabels': () => [],
    },
    actions: {
      'inboxes/get': vi.fn(),
      'agents/get': vi.fn(),
      'labels/get': vi.fn(),
    },
  });
  wrapper = shallowMount(ScheduledMessages, {
    global: { plugins: [store], directives: { 'on-clickaway': {} } },
  });
});
afterEach(() => wrapper.unmount());

describe('agenda transport editing', () => {
  it.each(['explicit', 'legacy_inbox'])(
    'preserves %s provider instead of the current default',
    async source => {
      await flushPromises();
      const state = wrapper.vm.$.setupState;
      const item = {
        ...schedule,
        whatsapp_transport_options: options,
        whatsapp_transport: {
          requested_provider: 'unoapi',
          selection_source: source,
        },
      };
      state.editingItem = item;
      state.resetEditForm(item);
      expect(state.editForm.whatsappProvider).toBe('unoapi');
      expect(state.isLegacyTransport).toBe(source === 'legacy_inbox');
      state.editForm.whatsappProvider = 'whatsapp_cloud';
      await state.saveEdit();
      expect(scheduledMessagesApi.update).toHaveBeenCalledWith(4, {
        scheduled_message: expect.objectContaining({
          whatsapp_transport: 'whatsapp_cloud',
        }),
      });
    }
  );

  it('does not send a transport field when editing an unlinked schedule', async () => {
    await flushPromises();
    const state = wrapper.vm.$.setupState;
    state.editingItem = schedule;
    state.resetEditForm(schedule);
    await state.saveEdit();
    const payload = scheduledMessagesApi.update.mock.calls[0][1];
    expect(payload.scheduled_message).not.toHaveProperty('whatsapp_transport');
  });

  it('fetches transport options for a searched conversation before creating', async () => {
    await flushPromises();
    ConversationsAPI.show.mockResolvedValue({
      data: { id: 9, whatsapp_transport_options: options },
    });
    const state = wrapper.vm.$.setupState;
    state.editMode = 'create';
    await state.selectConversation({
      conversation: { id: 9, inbox: { id: 7 } },
    });
    state.editForm.scheduledAt = '2030-10-20T12:00';
    state.editForm.labelId = 5;
    state.editForm.messages = [{ content: 'Later', attachments: [] }];
    expect(state.editForm.whatsappProvider).toBe('whatsapp_cloud');
    await state.saveEdit();
    expect(scheduledMessagesApi.create).toHaveBeenCalledWith({
      conversation_id: 9,
      scheduled_message: expect.objectContaining({
        whatsapp_transport: 'whatsapp_cloud',
      }),
    });
  });

  it('keeps agenda creation unchanged when the fetched conversation has no link', async () => {
    await flushPromises();
    ConversationsAPI.show.mockResolvedValue({ data: { id: 10 } });
    const state = wrapper.vm.$.setupState;
    state.editMode = 'create';
    await state.selectConversation({
      conversation: { id: 10, inbox: { id: 7 } },
    });
    state.editForm.scheduledAt = '2030-10-20T12:00';
    state.editForm.labelId = 5;
    state.editForm.messages = [{ content: 'Unlinked', attachments: [] }];
    await state.saveEdit();
    expect(
      scheduledMessagesApi.create.mock.calls[0][0].scheduled_message
    ).not.toHaveProperty('whatsapp_transport');
  });

  it('does not submit while the conversation transport is still loading', async () => {
    await flushPromises();
    const state = wrapper.vm.$.setupState;
    state.editMode = 'create';
    state.selectedConversation = { id: 10 };
    state.isLoadingConversation = true;
    state.editForm.scheduledAt = '2030-10-20T12:00';
    state.editForm.labelId = 5;
    await state.saveEdit();
    expect(scheduledMessagesApi.create).not.toHaveBeenCalled();
  });

  it('shows server validation errors without closing or discarding the edited schedule', async () => {
    await flushPromises();
    scheduledMessagesApi.update.mockRejectedValue({
      response: {
        status: 422,
        data: { errors: ['Link changed; review the schedule'] },
      },
    });
    const state = wrapper.vm.$.setupState;
    state.editingItem = schedule;
    state.resetEditForm(schedule);
    await state.saveEdit();
    expect(useAlert).toHaveBeenCalledWith('Link changed; review the schedule');
    expect(state.editForm.messages[0].content).toBe('Later');
    expect(state.isSaving).toBe(false);
  });
});
