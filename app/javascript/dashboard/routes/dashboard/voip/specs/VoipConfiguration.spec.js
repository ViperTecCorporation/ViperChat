import { mount, flushPromises } from '@vue/test-utils';
import AgentVoipCard from 'dashboard/components/voip/AgentVoipCard.vue';
import ServicesPage from '../ServicesPage.vue';
import TagInput from 'dashboard/components-next/taginput/TagInput.vue';

const mocks = vi.hoisted(() => ({
  accountId: null,
  profile: vi.fn(),
  services: vi.fn(),
  agents: vi.fn(),
  saveBinding: vi.fn(),
  saveService: vi.fn(),
  reloadProfile: vi.fn(),
  refreshConfiguration: vi.fn(),
  copy: vi.fn(),
  diagnostics: vi.fn(),
}));
vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: mocks.copy,
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
      diagnostics: serviceId => mocks.diagnostics(accountId, serviceId),
    };
  }),
}));
vi.mock('dashboard/stores/agentVoip', () => ({
  useAgentVoipStore: () => ({
    call: null,
    reloadProfile: mocks.reloadProfile,
    refreshConfiguration: mocks.refreshConfiguration,
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
    mocks.diagnostics.mockResolvedValue({
      data: {
        counts: {
          pending_events: 0,
          failed_events: 0,
          pending_artifacts: 0,
          failed_artifacts: 0,
        },
        records: [],
        truncated: false,
        recovery: { state: 'unsupported', cursor_configured: false },
      },
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

  it('shows the WSS validation failure instead of suggesting the administrator has no permissions', async () => {
    mocks.saveService.mockRejectedValueOnce({
      response: { status: 422, data: { attributes: ['wss_url'] } },
    });
    wrapper = mount(ServicesPage);
    await flushPromises();
    await wrapper.find('article button').trigger('click');
    await wrapper.find('dialog form').trigger('submit');
    await flushPromises();
    expect(wrapper.find('dialog [role="alert"]').text()).toBe(
      'AGENT_VOIP.WSS_REQUIRED'
    );
    expect(wrapper.find('dialog:has(form)').attributes()).toHaveProperty(
      'open'
    );
  });
  it('opens diagnostics only for the chosen integrated service and closes on account switch', async () => {
    mocks.services.mockResolvedValue({
      data: [{ id: 10, name: 'Central', integration_provider: 'webhook' }],
    });
    wrapper = mount(ServicesPage);
    await flushPromises();
    expect(mocks.diagnostics).not.toHaveBeenCalled();
    const button = wrapper
      .findAll('article button')
      .find(item => item.text() === 'AGENT_VOIP.DIAGNOSTICS.TITLE');
    await button.trigger('click');
    await flushPromises();
    expect(mocks.diagnostics).toHaveBeenCalledWith(1, 10);
    expect(wrapper.find('dialog[open]').text()).toContain('DIAGNOSTICS.HELP');
    mocks.accountId.value = 2;
    await flushPromises();
    expect(wrapper.find('dialog[open]').exists()).toBe(false);
  });

  it('lists configured extensions by agent and service without presenting the default as a live registration', async () => {
    mocks.services.mockResolvedValue({
      data: [
        {
          id: 10,
          name: 'Central',
          bindings: [
            { id: 21, agent_name: 'José', extension: '1001', active: true },
            { id: 22, agent_name: 'Maria', extension: '1002', active: false },
          ],
        },
      ],
    });
    wrapper = mount(ServicesPage);
    await flushPromises();
    const extensions = wrapper.findAll('li');
    expect(extensions).toHaveLength(2);
    expect(extensions[0].text()).toContain('1001');
    expect(extensions[0].text()).toContain('AGENT_VOIP.DEFAULT_EXTENSION');
    expect(extensions[1].text()).not.toContain('AGENT_VOIP.DEFAULT_EXTENSION');
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
    expect(wrapper.find('dialog:has(form)').attributes()).not.toHaveProperty(
      'open'
    );
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
    expect(wrapper.find('dialog:has(form)').attributes()).not.toHaveProperty(
      'open'
    );
    expect(wrapper.find('input[type="password"]').element.value).toBe('');
  });

  it('selects same-name agents independently and saves user IDs, not membership IDs', async () => {
    mocks.agents.mockResolvedValue({
      data: [
        { id: 50, user_id: 101, name: 'José' },
        { id: 51, user_id: 102, name: 'José' },
      ],
    });
    mocks.saveService.mockResolvedValue({ data: {} });
    wrapper = mount(ServicesPage);
    await flushPromises();
    await wrapper.find('header button').trigger('click');
    const selector = wrapper.findComponent(TagInput);
    expect(selector.props('skipLabelDedup')).toBe(true);
    selector.vm.$emit('add', { value: 101 });
    await flushPromises();
    expect(selector.props('menuItems').map(item => item.value)).toEqual([102]);
    selector.vm.$emit('add', { value: 102 });
    selector.vm.$emit('add', { value: 101 });
    await flushPromises();
    expect(selector.props('modelValue')).toEqual(['José', 'José']);
    await wrapper.find('dialog form').trigger('submit');
    expect(mocks.saveService).toHaveBeenLastCalledWith(
      1,
      null,
      expect.objectContaining({ allowed_user_ids: [101, 102] })
    );
  });

  it('preserves unavailable agents on edit and only allows all after explicit removal', async () => {
    mocks.services.mockResolvedValue({
      data: [{ id: 10, name: 'Central', allowed_user_ids: [999] }],
    });
    mocks.saveService.mockResolvedValue({ data: {} });
    wrapper = mount(ServicesPage);
    await flushPromises();
    await wrapper.find('article button').trigger('click');
    const selector = wrapper.findComponent(TagInput);
    expect(selector.props('modelValue')).toEqual([
      'AGENT_VOIP.UNAVAILABLE_AGENT',
    ]);
    await wrapper.find('dialog form').trigger('submit');
    expect(mocks.saveService).toHaveBeenLastCalledWith(
      1,
      10,
      expect.objectContaining({ allowed_user_ids: [999] })
    );
    await wrapper.find('article button').trigger('click');
    selector.vm.$emit('remove', 0);
    await wrapper.find('dialog form').trigger('submit');
    expect(mocks.saveService).toHaveBeenLastCalledWith(
      1,
      10,
      expect.objectContaining({ allowed_user_ids: [] })
    );
  });

  it('creates a SIP-only service by default and exposes webhook without AMI or legacy database settings', async () => {
    mocks.saveService.mockResolvedValue({ data: {} });
    wrapper = mount(ServicesPage);
    await flushPromises();
    await wrapper.find('header button').trigger('click');
    expect(wrapper.find('[name="integration_provider"]').element.value).toBe(
      'none'
    );
    expect(wrapper.find('[name="ami_host"]').exists()).toBe(false);
    await wrapper.find('[name="integration_provider"]').setValue('webhook');
    expect(wrapper.find('[name="ami_host"]').exists()).toBe(false);
    expect(wrapper.find('[name="history_api_url"]').exists()).toBe(false);
    expect(wrapper.find('dialog:has(form)').text()).toContain(
      'AGENT_VOIP.WEBHOOK_SAVE_FIRST'
    );
    expect(wrapper.find('dialog:has(form)').text()).toContain(
      'AGENT_VOIP.WEBHOOK_AUTH_HELP'
    );
    expect(wrapper.find('[name="api_access_token"]').exists()).toBe(false);
    await wrapper
      .find('[name="webhook_source_instance_id"]')
      .setValue('customer-pbx');
    await wrapper.find('dialog form').trigger('submit');
    expect(mocks.saveService).toHaveBeenLastCalledWith(
      1,
      null,
      expect.objectContaining({
        integration_provider: 'webhook',
        webhook_source_instance_id: 'customer-pbx',
      })
    );
  });

  it('edits the REST address while preserving omitted configured secrets and sends clear only explicitly', async () => {
    mocks.services.mockResolvedValue({
      data: [
        {
          id: 10,
          name: 'Central',
          integration_provider: 'viperconnect',
          ami_host: 'pbx.example.com',
          ami_port: 5039,
          ami_tls: true,
          ami_username: 'observer',
          ami_password_configured: true,
          history_api_url: 'https://pbx.example.com',
          history_company_id: 'company-safe-id',
          history_api_token_configured: true,
          webhook_source_instance_id: 'our-central',
          webhook_url:
            'https://chat.example.com/api/v1/accounts/1/voip/services/10/events',
        },
      ],
    });
    mocks.saveService.mockResolvedValue({ data: {} });
    wrapper = mount(ServicesPage);
    await flushPromises();
    await wrapper.find('article button').trigger('click');
    expect(wrapper.find('[name="ami_password"]').exists()).toBe(false);
    expect(wrapper.find('[name="webhook_url"]').element.value).toContain(
      '/services/10/events'
    );
    expect(wrapper.find('[name="history_api_token"]').element.value).toBe('');
    expect(wrapper.find('[name="history_company_id"]').element.value).toBe(
      'company-safe-id'
    );
    expect(
      wrapper.find('[name="history_company_id"]').attributes()
    ).toHaveProperty('required');
    expect(
      wrapper.find('[name="history_api_token"]').attributes('placeholder')
    ).toBe('AGENT_VOIP.SECRET_SAVED');
    await wrapper
      .find('[name="history_api_url"]')
      .setValue('https://new.example.com');
    await wrapper.find('dialog form').trigger('submit');
    expect(mocks.saveService).toHaveBeenLastCalledWith(
      1,
      10,
      expect.objectContaining({
        history_api_url: 'https://new.example.com',
        history_api_token: '',
        history_company_id: 'company-safe-id',
        clear_history_api_token: false,
      })
    );
    const submitted = mocks.saveService.mock.lastCall[2];
    expect(submitted).not.toHaveProperty('ami_host');
    expect(submitted).not.toHaveProperty('ami_password');
    expect(submitted).not.toHaveProperty('webhook_url');
    expect(submitted).not.toHaveProperty('history_api_token_configured');
    await wrapper.find('article button').trigger('click');
    await wrapper.find('[name="clear_history_api_token"]').setValue(true);
    expect(
      wrapper.find('[name="history_api_token"]').attributes()
    ).toHaveProperty('disabled');
    await wrapper.find('dialog form').trigger('submit');
    expect(mocks.saveService).toHaveBeenLastCalledWith(
      1,
      10,
      expect.objectContaining({ clear_history_api_token: true })
    );
  });

  it('clears transient integration credentials on closing the editor', async () => {
    wrapper = mount(ServicesPage);
    await flushPromises();
    await wrapper.find('header button').trigger('click');
    await wrapper
      .find('[name="integration_provider"]')
      .setValue('viperconnect');
    await wrapper
      .find('[name="history_api_token"]')
      .setValue('api-test-secret');
    await wrapper.find('dialog:has(form)').trigger('close');
    expect(wrapper.find('[name="history_api_token"]').element.value).toBe('');
  });

  it('copies only the dedicated URL and reports success or failure without exposing a token', async () => {
    const webhookUrl =
      'https://chat.example.com/api/v1/accounts/1/voip/services/10/events';
    mocks.services.mockResolvedValue({
      data: [
        {
          id: 10,
          name: 'PBX',
          integration_provider: 'webhook',
          webhook_url: webhookUrl,
          webhook_source_instance_id: 'pbx-client',
        },
      ],
    });
    wrapper = mount(ServicesPage);
    await flushPromises();
    await wrapper.find('article button').trigger('click');
    const copyButton = wrapper
      .findAll('dialog button')
      .find(button => button.text() === 'AGENT_VOIP.WEBHOOK_COPY');
    mocks.copy.mockResolvedValueOnce();
    await copyButton.trigger('click');
    await flushPromises();
    expect(mocks.copy).toHaveBeenCalledWith(webhookUrl);
    expect(wrapper.find('[role="status"]').text()).toBe(
      'AGENT_VOIP.WEBHOOK_COPIED'
    );
    mocks.copy.mockRejectedValueOnce(new Error('clipboard unavailable'));
    await copyButton.trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="status"]').text()).toBe(
      'AGENT_VOIP.WEBHOOK_COPY_FAILED'
    );
    expect(wrapper.find('[name="api_access_token"]').exists()).toBe(false);
  });

  it('does not submit hidden REST credentials when changing to an external webhook producer', async () => {
    mocks.services.mockResolvedValue({
      data: [
        {
          id: 10,
          name: 'PBX',
          integration_provider: 'viperconnect',
          history_api_url: 'https://central.example.com',
          history_api_token_configured: true,
          webhook_source_instance_id: 'pbx-client',
        },
      ],
    });
    mocks.saveService.mockResolvedValue({ data: {} });
    wrapper = mount(ServicesPage);
    await flushPromises();
    await wrapper.find('article button').trigger('click');
    await wrapper.find('[name="history_api_token"]').setValue('unsaved-secret');
    await wrapper.find('[name="integration_provider"]').setValue('webhook');
    expect(wrapper.find('[name="history_api_token"]').exists()).toBe(false);
    await wrapper.find('dialog form').trigger('submit');
    const submitted = mocks.saveService.mock.lastCall[2];
    expect(submitted.integration_provider).toBe('webhook');
    expect(submitted).not.toHaveProperty('history_api_token');
    expect(submitted).not.toHaveProperty('history_api_url');
    expect(submitted).not.toHaveProperty('clear_history_api_token');
  });
});
