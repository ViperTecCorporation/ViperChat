import { mount, flushPromises } from '@vue/test-utils';
import CallsPage from '../CallsPage.vue';

const mocks = vi.hoisted(() => ({
  calls: vi.fn(),
  favorites: vi.fn(),
  removeFavorite: vi.fn(),
  call: vi.fn(),
  push: vi.fn(),
  dial: vi.fn(),
  openDialer: vi.fn(),
  route: null,
  accountId: null,
}));
vi.mock('dashboard/composables/useAccount', async () => {
  const { ref } = await import('vue');
  return {
    useAccount: () => {
      mocks.accountId = ref(1);
      return {
        accountId: mocks.accountId,
        accountScopedRoute: (name, params) => ({ name, params }),
      };
    },
  };
});
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  return {
    useRoute: () => {
      mocks.route = reactive({ params: {} });
      return mocks.route;
    },
    useRouter: () => ({ push: mocks.push }),
  };
});
vi.mock('dashboard/routes/index', () => ({ default: { push: mocks.push } }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: { getCurrentRole: 'agent' } }),
}));
vi.mock('dashboard/api/voip', () => ({
  VoipAPI: vi.fn(function api(accountId) {
    return { ...mocks, accountId: Number(accountId) };
  }),
}));
vi.mock('dashboard/stores/agentVoip', () => ({
  useAgentVoipStore: () => ({
    services: [{ id: 1, name: 'First service' }],
    connected: true,
    call: null,
    registration: 'registered',
    activeBinding: { voip_service_id: 1, extension: '0010' },
    dial: mocks.dial,
    openDialer: mocks.openDialer,
  }),
}));
vi.mock('dashboard/components/voip/AgentVoipCard.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('dashboard/components-next/avatar/Avatar.vue', () => ({
  default: { template: '<div />' },
}));

describe('Calls page service-safe dialing', () => {
  let wrapper;
  beforeEach(() => {
    mocks.removeFavorite.mockResolvedValue({});
    mocks.calls.mockResolvedValue({ data: { items: [], total: 0 } });
    mocks.favorites.mockResolvedValue({
      data: [
        { id: 1, voip_service_id: 1, name: 'Same central', address: '0020' },
        { id: 2, voip_service_id: 2, name: 'Other central', address: '0030' },
      ],
    });
    Object.defineProperty(HTMLDialogElement.prototype, 'showModal', {
      configurable: true,
      value: function show() {
        this.setAttribute('open', '');
      },
    });
    Object.defineProperty(HTMLDialogElement.prototype, 'close', {
      configurable: true,
      value: function close() {
        this.removeAttribute('open');
      },
    });
  });
  afterEach(() => {
    wrapper?.unmount();
    delete HTMLDialogElement.prototype.showModal;
    delete HTMLDialogElement.prototype.close;
    vi.restoreAllMocks();
  });

  it('opens the dialer for the explicitly active service without initiating a call', async () => {
    wrapper = mount(CallsPage);
    await flushPromises();
    const button = wrapper
      .findAll('button')
      .find(item => item.text() === 'Same central');
    await button.trigger('click');
    expect(mocks.openDialer).toHaveBeenCalledWith({
      address: '0020',
      serviceId: 1,
    });
    expect(mocks.dial).not.toHaveBeenCalled();
  });

  it('opens a different service favorite explicitly without silently activating or dialing it', async () => {
    wrapper = mount(CallsPage);
    await flushPromises();
    const button = wrapper
      .findAll('button')
      .find(item => item.text() === 'Other central');
    await button.trigger('click');
    expect(mocks.openDialer).toHaveBeenCalledWith({
      address: '0030',
      serviceId: 2,
    });
    expect(mocks.dial).not.toHaveBeenCalled();
  });

  it('uses the conversation back arrow before the detail title and returns to the calls list', async () => {
    mocks.call.mockResolvedValue({
      data: {
        id: 25,
        service_id: 1,
        remote_address: '0020',
        direction: 'outgoing',
        state: 'ended',
      },
    });
    wrapper = mount(CallsPage);
    mocks.route.params.callId = '25';
    await flushPromises();
    const back = wrapper.find('button[aria-label="AGENT_VOIP.BACK"]');
    expect(back.find('.i-lucide-chevron-left').exists()).toBe(true);
    expect(back.text()).toBe('');
    expect(back.element.nextElementSibling.textContent.trim()).toBe(
      'AGENT_VOIP.DETAIL'
    );
    await back.trigger('click');
    expect(mocks.push).toHaveBeenCalledWith({
      name: 'agent_voip_calls',
      params: undefined,
    });
  });

  it('distinguishes missed, incoming and outgoing calls with decorative icons and readable states', async () => {
    mocks.calls.mockResolvedValue({
      data: {
        items: [
          { id: 1, remote_name: 'Ana', direction: 'incoming', state: 'missed' },
          { id: 2, remote_name: 'Bia', direction: 'incoming', state: 'ended' },
          { id: 3, remote_name: 'Caio', direction: 'outgoing', state: 'ended' },
        ],
        total: 3,
      },
    });
    wrapper = mount(CallsPage);
    await flushPromises();
    [
      'phone-missed',
      'phone-incoming',
      'phone-outgoing',
      'search',
      'history',
      'star',
    ].forEach(icon => {
      expect(
        wrapper.find(`.i-lucide-${icon}[aria-hidden="true"]`).exists()
      ).toBe(true);
    });
    expect(wrapper.text()).toContain('AGENT_VOIP.STATE.missed');
    expect(wrapper.text()).toContain('AGENT_VOIP.DIRECTION.outgoing');
    expect(mocks.dial).not.toHaveBeenCalled();
  });

  it('keeps filters collapsed without clearing selections and shows the active count', async () => {
    wrapper = mount(CallsPage);
    await flushPromises();
    const toggle = wrapper.find('button[aria-controls="voip-call-filters"]');
    expect(toggle.attributes('aria-expanded')).toBe('false');
    expect(wrapper.find('#voip-call-filters').attributes()).not.toHaveProperty(
      'open'
    );
    await toggle.trigger('click');
    expect(wrapper.find('#voip-call-filters').attributes()).toHaveProperty(
      'open'
    );
    await wrapper
      .find('select[aria-label="AGENT_VOIP.FILTER_STATE"]')
      .setValue('missed');
    await wrapper
      .find('#voip-call-filters button[aria-label="AGENT_VOIP.CLOSE"]')
      .trigger('click');
    await wrapper.find('#voip-call-filters').trigger('close');
    expect(wrapper.find('#voip-call-filters').attributes()).not.toHaveProperty(
      'open'
    );
    expect(toggle.attributes('aria-expanded')).toBe('false');
    expect(toggle.text()).toContain('1');
    expect(
      wrapper.find('select[aria-label="AGENT_VOIP.FILTER_STATE"]').element.value
    ).toBe('missed');
  });

  it('paginates favorites so they cannot push the history out of view indefinitely', async () => {
    mocks.favorites.mockResolvedValue({
      data: Array.from({ length: 7 }, (_, i) => ({
        id: i + 1,
        voip_service_id: 1,
        name: `Favorite ${i + 1}`,
        address: `00${i + 1}`,
      })),
    });
    wrapper = mount(CallsPage);
    await flushPromises();
    expect(wrapper.text()).toContain('Favorite 1');
    expect(wrapper.text()).toContain('Favorite 3');
    expect(wrapper.text()).not.toContain('Favorite 4');
    await wrapper.find('button[aria-label="AGENT_VOIP.NEXT"]').trigger('click');
    expect(wrapper.text()).toContain('Favorite 4');
    expect(wrapper.text()).not.toContain('Favorite 1');
    await wrapper
      .find('button[aria-label="AGENT_VOIP.PREVIOUS"]')
      .trigger('click');
    expect(wrapper.text()).toContain('Favorite 1');
    expect(mocks.dial).not.toHaveBeenCalled();
  });

  it('orders favorites, search and recent calls, with filter and new-call icons in the recent toolbar', async () => {
    wrapper = mount(CallsPage);
    await flushPromises();
    const headings = wrapper.findAll('h2');
    const favorites = headings.find(
      heading => heading.text() === 'AGENT_VOIP.FAVORITES'
    );
    const recent = headings.find(
      heading => heading.text() === 'AGENT_VOIP.RECENT'
    );
    const search = wrapper.find('input[type="search"]');
    expect(favorites.element.compareDocumentPosition(search.element)).toBe(
      Node.DOCUMENT_POSITION_FOLLOWING
    );
    expect(search.element.compareDocumentPosition(recent.element)).toBe(
      Node.DOCUMENT_POSITION_FOLLOWING
    );
    expect(
      recent.element.parentElement.querySelector(
        '[aria-controls="voip-call-filters"]'
      )
    ).not.toBeNull();
    expect(
      recent.element.parentElement.querySelector(
        'button[aria-label="AGENT_VOIP.NEW_CALL"]'
      )
    ).not.toBeNull();
    expect(wrapper.find('details').exists()).toBe(false);
  });

  it('shows five calls per server page, replacing the previous page rather than accumulating rows', async () => {
    const row = {
      id: 1,
      remote_name: 'First call',
      direction: 'incoming',
      state: 'ended',
    };
    mocks.calls
      .mockResolvedValueOnce({ data: { items: [row], total: 6 } })
      .mockResolvedValueOnce({
        data: {
          items: [{ ...row, id: 6, remote_name: 'Next call' }],
          total: 6,
        },
      });
    wrapper = mount(CallsPage);
    await flushPromises();
    await wrapper
      .find(
        'nav[aria-label="AGENT_VOIP.RECENT"] button[aria-label="AGENT_VOIP.NEXT"]'
      )
      .trigger('click');
    await flushPromises();
    expect(mocks.calls).toHaveBeenLastCalledWith(
      expect.objectContaining({ page: 2 })
    );
    expect(
      wrapper
        .findAll('button')
        .filter(button => button.text().includes('First call'))
    ).toHaveLength(0);
    expect(wrapper.text()).toContain('Next call');
  });

  it('asks for confirmation before removing only a favorite shortcut', async () => {
    wrapper = mount(CallsPage);
    await flushPromises();
    const pin = wrapper.findAll(
      'button[aria-label="AGENT_VOIP.REMOVE_FAVORITE"]'
    )[0];
    expect(pin.find('.i-lucide-pin-off').exists()).toBe(true);
    await pin.trigger('click');
    const dialog = wrapper.find(
      'dialog[aria-label="AGENT_VOIP.REMOVE_FAVORITE"]'
    );
    expect(dialog.attributes()).toHaveProperty('open');
    expect(mocks.removeFavorite).not.toHaveBeenCalled();
    await dialog
      .findAll('button')
      .find(button => button.text() === 'AGENT_VOIP.CANCEL')
      .trigger('click');
    expect(mocks.removeFavorite).not.toHaveBeenCalled();
    await pin.trigger('click');
    await dialog
      .findAll('button')
      .find(button => button.text() === 'AGENT_VOIP.REMOVE_FAVORITE')
      .trigger('click');
    await flushPromises();
    expect(mocks.removeFavorite).toHaveBeenCalledExactlyOnceWith(1);
    expect(mocks.dial).not.toHaveBeenCalled();
  });

  it('does not show favorites returned late from the previously selected account', async () => {
    let resolveOld;
    mocks.favorites
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            resolveOld = resolve;
          })
      )
      .mockResolvedValueOnce({ data: [] });
    wrapper = mount(CallsPage);
    await flushPromises();
    mocks.accountId.value = 2;
    await flushPromises();
    resolveOld({
      data: [
        {
          id: 99,
          voip_service_id: 1,
          name: 'Previous account private favorite',
          address: '0099',
        },
      ],
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('Previous account private favorite');
  });
});
