import { mount, flushPromises } from '@vue/test-utils';
import AgentVoipCard from 'dashboard/components/voip/AgentVoipCard.vue';
import ServicesPage from '../ServicesPage.vue';

const mocks = vi.hoisted(() => ({
  accountId: null,
  profile: vi.fn(),
  services: vi.fn(),
  agents: vi.fn(),
  saveBinding: vi.fn(),
  saveService: vi.fn(),
  reloadProfile: vi.fn(),
}));
vi.mock('dashboard/composables/useAccount', async () => {
  const { ref } = await import('vue');
  return {
    useAccount: () => {
      mocks.accountId ||= ref(1);
      return { accountId: mocks.accountId };
    },
  };
});
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: { getCurrentRole: 'administrator' } }),
}));
vi.mock('dashboard/api/voip', () => ({
  VoipAPI: vi.fn(function api(accountId) {
    return {
      profile: (...args) => mocks.profile(accountId, ...args),
      services: () => mocks.services(accountId),
      agents: () => mocks.agents(accountId),
      saveBinding: (...args) => mocks.saveBinding(accountId, ...args),
      saveService: (...args) => mocks.saveService(accountId, ...args),
    };
  }),
}));
vi.mock('dashboard/stores/agentVoip', () => ({
  useAgentVoipStore: () => ({
    call: null,
    reloadProfile: mocks.reloadProfile,
  }),
}));

describe('VoIP configuration account isolation', () => {
  let wrapper;
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.accountId = null;
    mocks.profile.mockResolvedValue({
      data: {
        services: [{ id: 10, name: 'Central' }],
        bindings: [
          { id: 20, voip_service_id: 10, active: true, extension: '1001' },
        ],
      },
    });
    mocks.services.mockResolvedValue({ data: [{ id: 10, name: 'Central' }] });
    mocks.agents.mockResolvedValue({ data: [] });
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
  });

  it('reloads the saved extension when reopening an unchanged service', async () => {
    wrapper = mount(AgentVoipCard);
    await flushPromises();
    await wrapper.find('button').trigger('click');
    await flushPromises();
    await wrapper.find('input[maxlength="64"]').setValue('unsaved');
    wrapper.find('dialog').element.close();
    await wrapper.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('input[maxlength="64"]').element.value).toBe('1001');
  });

  it('clears credentials and ignores a pending old-account profile on account switch', async () => {
    wrapper = mount(AgentVoipCard);
    await flushPromises();
    await wrapper.find('button').trigger('click');
    await flushPromises();
    await wrapper.find('input[type="password"]').setValue('secret');
    let resolveOld;
    mocks.profile.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    await wrapper.find('button').trigger('click');
    mocks.profile.mockResolvedValue({ data: { services: [], bindings: [] } });
    mocks.accountId.value = 2;
    await flushPromises();
    resolveOld({ data: { services: [{ id: 10 }], bindings: [] } });
    await flushPromises();
    expect(wrapper.find('dialog').attributes()).not.toHaveProperty('open');
    expect(wrapper.find('input[type="password"]').exists()).toBe(false);
    await wrapper.find('form').trigger('submit');
    expect(mocks.saveBinding).not.toHaveBeenCalled();
  });

  it('closes the service editor and excludes late services from the old account', async () => {
    let resolveOld;
    mocks.services.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    wrapper = mount(ServicesPage);
    await wrapper.find('header button').trigger('click');
    await wrapper.find('input[type="password"]').setValue('turn-secret');
    mocks.services.mockResolvedValue({
      data: [{ id: 30, name: 'New central' }],
    });
    mocks.accountId.value = 2;
    await flushPromises();
    resolveOld({ data: [{ id: 10, name: 'Old central' }] });
    await flushPromises();
    expect(wrapper.text()).toContain('New central');
    expect(wrapper.text()).not.toContain('Old central');
    expect(wrapper.find('dialog').attributes()).not.toHaveProperty('open');
    expect(wrapper.find('input[type="password"]').element.value).toBe('');
  });
});
