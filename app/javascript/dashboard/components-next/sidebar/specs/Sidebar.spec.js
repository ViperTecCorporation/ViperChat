import { shallowMount, RouterLinkStub } from '@vue/test-utils';
import { ref } from 'vue';
import Sidebar from '../Sidebar.vue';

const state = vi.hoisted(() => ({ width: 390, collapsed: false }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: name => ({ name }),
    isOnChatwootCloud: false,
  }),
}));
vi.mock('dashboard/composables/utils/useKbd', () => ({
  useKbd: () => 'Ctrl+K',
}));
vi.mock('../useSidebarKeyboardShortcuts', () => ({
  useSidebarKeyboardShortcuts: vi.fn(),
}));
vi.mock('../provider', () => ({
  provideSidebarContext: vi.fn(),
  useSidebarResize: () => ({
    sidebarWidth: ref(200),
    isCollapsed: ref(state.collapsed),
    setSidebarWidth: vi.fn(),
    saveWidth: vi.fn(),
    snapToCollapsed: vi.fn(),
    snapToExpanded: vi.fn(),
    COLLAPSED_THRESHOLD: 160,
  }),
}));
vi.mock('@vueuse/core', async importOriginal => ({
  ...(await importOriginal()),
  useWindowSize: () => ({ width: ref(state.width) }),
}));
vi.mock('vuex', async importOriginal => ({
  ...(await importOriginal()),
  useStore: () => ({ dispatch: vi.fn() }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key => {
    if (key === 'notifications/getUnreadCount') return ref(0);
    if (key === 'accounts/isFeatureEnabledonAccount') return ref(() => false);
    if (key === 'sidebarSortPreferences/getSectionSort')
      return ref(() => undefined);
    if (/get(Inbox|Label|Team|Folder)UnreadCount/.test(key))
      return ref(() => 0);
    if (['getCurrentAccountId', 'getCurrentUserID'].includes(key))
      return ref(1);
    if (
      /get(Inboxes|LabelsOnSidebar|MyTeams|ContactCustomViews|ConversationCustomViews)/.test(
        key
      )
    )
      return ref([]);
    return ref(false);
  },
}));

const global = {
  stubs: {
    RouterLink: RouterLinkStub,
    SidebarGroup: { props: ['children'], template: '<div />' },
  },
};

describe('sidebar search navigation', () => {
  it.each([320, 360, 390, 412, 430])(
    'closes the mobile menu when search is selected at %s px',
    async width => {
      state.width = width;
      state.collapsed = false;
      const wrapper = shallowMount(Sidebar, {
        props: { isMobileSidebarOpen: true },
        global,
      });
      await wrapper.getComponent(RouterLinkStub).trigger('click');
      expect(wrapper.getComponent(RouterLinkStub).props('to')).toEqual({
        name: 'search',
      });
      expect(wrapper.emitted('closeMobileSidebar')).toHaveLength(1);
      wrapper.unmount();
    }
  );
  it.each([false, true])(
    'does not change desktop sidebar width or emit a mobile close (collapsed: %s)',
    async collapsed => {
      state.width = 1280;
      state.collapsed = collapsed;
      const wrapper = shallowMount(Sidebar, { global });
      await wrapper.getComponent(RouterLinkStub).trigger('click');
      expect(wrapper.emitted('closeMobileSidebar')).toBeUndefined();
      wrapper.unmount();
    }
  );
});
