import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { ref } from 'vue';
import ConversationItem from '../ConversationItem.vue';

const mocks = vi.hoisted(() => ({
  setPinned: vi.fn(),
  setArchived: vi.fn(),
  push: vi.fn(),
  alert: vi.fn(),
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: mocks.push }) }));
vi.mock('dashboard/composables', () => ({ useAlert: mocks.alert }));
vi.mock('dashboard/composables/useConversationArchives', () => ({
  useConversationArchives: () => ({ setArchived: mocks.setArchived }),
}));
vi.mock('dashboard/composables/useConversationPins', () => ({
  useConversationPins: () => ({
    isPinned: () => false,
    setPinned: mocks.setPinned,
  }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const mount = (tab = 'all', assigneeId = 2) =>
  shallowMount(ConversationItem, {
    props: {
      source: {
        id: 7,
        inbox_id: 1,
        meta: { assignee: { id: assigneeId, name: 'Ana' }, team: { id: 1 } },
        labels: [],
      },
    },
    global: {
      plugins: [
        createStore({
          getters: {
            getSelectedChat: () => ({}),
            'inboxes/getInboxes': () => [],
            getSelectedInbox: () => null,
            getCurrentAccountId: () => 1,
            getCurrentUser: () => ({ id: 2 }),
            'inboxes/getInbox': () => () => ({ id: 1 }),
          },
        }),
      ],
      provide: {
        activeAssigneeTab: ref(tab),
        ...Object.fromEntries(
          [
            'selectConversation',
            'deSelectConversation',
            'assignAgent',
            'assignTeam',
            'assignLabels',
            'removeLabels',
            'updateConversationStatus',
            'toggleContextMenu',
            'markAsUnread',
            'markAsRead',
            'assignPriority',
            'isConversationSelected',
            'deleteConversation',
          ].map(key => [key, vi.fn()])
        ),
      },
      stubs: { ContextMenu: { template: '<div><slot /></div>' } },
    },
  });

describe('conversation list pin actions', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.setPinned.mockResolvedValue();
    mocks.setArchived.mockResolvedValue();
  });
  afterEach(() => vi.useRealTimers());
  it.each([
    ['me', 2, true],
    ['all', 2, false],
    ['me', 3, false],
  ])(
    'restricts archive in tab %s with assignee %s',
    async (tab, assigneeId, allowed) => {
      const wrapper = mount(tab, assigneeId);
      wrapper
        .findComponent({ name: 'ConversationCard' })
        .vm.$emit('contextmenu', { preventDefault() {}, pageX: 5, pageY: 5 });
      await flushPromises();
      const menu = wrapper.findComponent({ name: 'ConversationContextMenu' });
      expect(menu.props('canArchive')).toBe(allowed);
      menu.vm.$emit('archive');
      await flushPromises();
      expect(mocks.setArchived).toHaveBeenCalledTimes(allowed ? 1 : 0);
      if (allowed) expect(mocks.setArchived).toHaveBeenCalledWith(7, true);
      wrapper.unmount();
    }
  );
  it('shows the agent for team conversations even when the tab hides assignees', () => {
    const wrapper = mount();
    expect(
      wrapper.findComponent({ name: 'ConversationCard' }).props('showAssignee')
    ).toBe(true);
    wrapper.unmount();
  });
  it('pins through the context menu', async () => {
    const wrapper = mount();
    wrapper
      .findComponent({ name: 'ConversationCard' })
      .vm.$emit('contextmenu', { preventDefault() {}, pageX: 5, pageY: 5 });
    await flushPromises();
    wrapper
      .findComponent({ name: 'ConversationContextMenu' })
      .vm.$emit('togglePin');
    await flushPromises();
    expect(mocks.setPinned).toHaveBeenCalledWith(7, true);
    wrapper.unmount();
  });
  it('opens the menu on long press without navigating', async () => {
    vi.useFakeTimers();
    const wrapper = mount();
    const card = wrapper.findComponent({ name: 'ConversationCard' });
    await card.trigger('touchstart', {
      touches: [{ clientX: 20, clientY: 20, pageX: 20, pageY: 20 }],
    });
    await vi.advanceTimersByTimeAsync(550);
    await card.trigger('touchend');
    card.vm.$emit('click', {});
    expect(mocks.push).not.toHaveBeenCalled();
    expect(
      wrapper.findComponent({ name: 'ConversationContextMenu' }).exists()
    ).toBe(true);
    wrapper.unmount();
  });
  it('cancels the long press when scrolling', async () => {
    vi.useFakeTimers();
    const wrapper = mount();
    const card = wrapper.findComponent({ name: 'ConversationCard' });
    await card.trigger('touchstart', {
      touches: [{ clientX: 20, clientY: 20 }],
    });
    await card.trigger('touchmove', {
      touches: [{ clientX: 20, clientY: 50 }],
    });
    await vi.advanceTimersByTimeAsync(600);
    expect(
      wrapper.findComponent({ name: 'ConversationContextMenu' }).exists()
    ).toBe(false);
    wrapper.unmount();
  });
});
