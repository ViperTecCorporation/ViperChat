import { mount, flushPromises } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import AgentDialer from '../AgentDialer.vue';

const mocks = vi.hoisted(() => ({
  phone: null,
  directory: vi.fn(),
  account: null,
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: mocks.account }),
}));
vi.mock('dashboard/stores/agentVoip', () => ({
  useAgentVoipStore: () => mocks.phone,
}));
vi.mock('dashboard/api/voip', () => ({
  VoipAPI: class API {
    directory = mocks.directory;
  },
}));

describe('AgentDialer explicit global calling', () => {
  let wrapper;
  beforeEach(() => {
    mocks.account = ref(1);
    mocks.directory.mockResolvedValue({
      data: {
        items: [
          {
            id: 5,
            kind: 'contact',
            name: 'Synthetic contact',
            address: '+5566999990000',
          },
        ],
        total: 16,
        page: 1,
      },
    });
    mocks.phone = reactive({
      dialer: { open: false, address: '', serviceId: null, kind: 'manual' },
      services: [
        { id: 1, name: 'Central' },
        { id: 2, name: 'Other' },
      ],
      bindings: [
        { id: 10, voip_service_id: 1, credential_configured: true },
        { id: 20, voip_service_id: 2, credential_configured: true },
      ],
      activeService: { id: 1 },
      connected: true,
      call: null,
      dial: vi.fn().mockResolvedValue(),
      activate: vi.fn().mockResolvedValue(),
      closeDialer: vi.fn(() => {
        mocks.phone.dialer.open = false;
      }),
    });
    HTMLDialogElement.prototype.showModal = vi.fn();
    HTMLDialogElement.prototype.close = vi.fn();
    wrapper = mount(AgentDialer, { attachTo: document.body });
  });
  afterEach(() => {
    wrapper.unmount();
    document.body.innerHTML = '';
    vi.clearAllMocks();
  });

  it('selects directory entries and pages without placing a call', async () => {
    mocks.phone.dialer = {
      open: true,
      address: '',
      serviceId: 1,
      kind: 'contacts',
    };
    await flushPromises();
    expect(mocks.directory).toHaveBeenLastCalledWith({
      service_id: 1,
      kind: 'contacts',
      search: '',
      page: 1,
    });
    const dialog = document.querySelector('dialog');
    [...dialog.querySelectorAll('button')]
      .find(button => button.textContent.includes('Synthetic contact'))
      .click();
    await flushPromises();
    expect(mocks.phone.dial).not.toHaveBeenCalled();
    expect(dialog.querySelector('input[inputmode="tel"]').value).toBe(
      '+5566999990000'
    );
    dialog.querySelector('button[aria-label="AGENT_VOIP.NEXT"]').click();
    await flushPromises();
    expect(mocks.directory).toHaveBeenLastCalledWith(
      expect.objectContaining({ page: 2 })
    );
  });

  it('requires explicit service activation and a separate confirmed call', async () => {
    mocks.phone.dialer = {
      open: true,
      address: '+55 (66) 99999-0000',
      serviceId: 2,
      kind: 'manual',
    };
    await flushPromises();
    const dialog = document.querySelector('dialog');
    expect(dialog.querySelector('button[type="submit"]').disabled).toBe(true);
    expect(mocks.phone.activate).not.toHaveBeenCalled();
    [...dialog.querySelectorAll('button')]
      .find(button => button.textContent.includes('AGENT_VOIP.ACTIVATE'))
      .click();
    await flushPromises();
    expect(mocks.phone.activate).toHaveBeenCalledWith(20);
    expect(mocks.phone.dial).not.toHaveBeenCalled();
    mocks.phone.activeService = { id: 2 };
    await flushPromises();
    dialog
      .querySelector('form')
      .dispatchEvent(new Event('submit', { cancelable: true }));
    await flushPromises();
    expect(mocks.phone.dial).toHaveBeenCalledWith('+5566999990000');
    expect(mocks.phone.closeDialer).toHaveBeenCalled();
  });

  it('does not accept a LID as a manual telephone destination and closes on Escape', async () => {
    mocks.phone.dialer = {
      open: true,
      address: '12345@lid',
      serviceId: 1,
      kind: 'manual',
    };
    await flushPromises();
    const dialog = document.querySelector('dialog');
    expect(dialog.querySelector('button[type="submit"]').disabled).toBe(true);
    dialog.dispatchEvent(new Event('cancel', { cancelable: true }));
    await flushPromises();
    expect(mocks.phone.closeDialer).toHaveBeenCalled();
    expect(mocks.phone.dial).not.toHaveBeenCalled();
  });

  it('scopes the extension directory to the selected service without automatically calling an agent', async () => {
    mocks.phone.dialer = {
      open: true,
      address: '',
      serviceId: 2,
      kind: 'extensions',
    };
    await flushPromises();
    expect(mocks.directory).toHaveBeenLastCalledWith({
      service_id: 2,
      kind: 'extensions',
      search: '',
      page: 1,
    });
    expect(mocks.phone.activate).not.toHaveBeenCalled();
    expect(mocks.phone.dial).not.toHaveBeenCalled();
  });

  it('closes and ignores late directory responses when switching accounts', async () => {
    let resolveDirectory;
    mocks.directory.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveDirectory = resolve;
        })
    );
    mocks.phone.dialer = {
      open: true,
      address: '0020',
      serviceId: 1,
      kind: 'contacts',
    };
    await flushPromises();
    mocks.account.value = 2;
    await flushPromises();
    resolveDirectory({
      data: {
        items: [{ id: 99, name: 'Old account contact', address: '9999' }],
        total: 1,
      },
    });
    await flushPromises();
    expect(mocks.phone.closeDialer).toHaveBeenCalled();
    expect(document.querySelector('dialog').textContent).not.toContain(
      'Old account contact'
    );
    expect(document.querySelector('input[inputmode="tel"]').value).toBe('');
  });
});
