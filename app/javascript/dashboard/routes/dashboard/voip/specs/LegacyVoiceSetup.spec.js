import { mount, flushPromises } from '@vue/test-utils';
import Voice from '../../settings/inbox/channels/Voice.vue';

const mocks = vi.hoisted(() => ({ dispatch: vi.fn(), replace: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', async () => {
  const { ref } = await import('vue');
  return {
    useStore: () => ({ dispatch: mocks.dispatch }),
    useMapGetter: () => ref({ isCreating: false }),
  };
});

describe('Voice inbox setup after agent SIP decoupling', () => {
  let wrapper;
  beforeEach(() => {
    mocks.dispatch.mockResolvedValue({ id: 55 });
    wrapper = mount(Voice, {
      global: {
        stubs: {
          PageHeader: true,
          Input: true,
          NextButton: true,
          VoipSetupNotice: {
            template: '<p data-testid="agent-voip-notice">Agent VoIP setup</p>',
          },
        },
      },
    });
  });
  afterEach(() => wrapper.unmount());

  it('redirects custom SIP configuration away from inbox creation without creating a legacy Voice inbox', async () => {
    await wrapper.find('select').setValue('custom');
    expect(wrapper.find('[data-testid="agent-voip-notice"]').exists()).toBe(
      true
    );
    expect(wrapper.findAll('input-stub')).toHaveLength(0);
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(mocks.dispatch).not.toHaveBeenCalled();
  });

  it('keeps Twilio creation and credentials unchanged', async () => {
    Object.assign(wrapper.vm.state, {
      phoneNumber: '+15551234567',
      accountSid: 'synthetic-account',
      authToken: 'synthetic-token',
      apiKeySid: 'synthetic-key',
      apiKeySecret: 'synthetic-secret',
    });
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(mocks.dispatch).toHaveBeenCalledWith('inboxes/createVoiceChannel', {
      name: 'Voice (+15551234567)',
      voice: {
        phone_number: '+15551234567',
        provider: 'twilio',
        provider_config: {
          account_sid: 'synthetic-account',
          auth_token: 'synthetic-token',
          api_key_sid: 'synthetic-key',
          api_key_secret: 'synthetic-secret',
        },
      },
    });
    expect(mocks.replace).toHaveBeenCalledWith({
      name: 'settings_inboxes_add_agents',
      params: { page: 'new', inbox_id: 55 },
    });
  });
});
