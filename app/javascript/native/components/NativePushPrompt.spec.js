import { flushPromises, mount } from '@vue/test-utils';

const mocks = vi.hoisted(() => ({
  appStateCallback: null,
  enableNativePush: vi.fn(),
  initializeNativePush: vi.fn(),
  openNotificationSettings: vi.fn(),
}));

vi.mock('@capacitor/app', () => ({
  App: {
    addListener: vi.fn(async (_event, callback) => {
      mocks.appStateCallback = callback;
      return { remove: vi.fn() };
    }),
  },
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({ currentRoute: { value: { params: {} } } }),
}));

vi.mock('../platform/nativePushService', () => ({
  enableNativePush: mocks.enableNativePush,
  initializeNativePush: mocks.initializeNativePush,
}));

vi.mock('../platform/nativeAppSettingsService', () => ({
  openNativeNotificationSettings: mocks.openNotificationSettings,
}));

describe('NativePushPrompt', () => {
  let NativePushPrompt;

  beforeAll(async () => {
    window.viperNativeInstallation = {
      installationId: 'installation-123',
      features: { nativePush: true },
    };
    ({ default: NativePushPrompt } = await import('./NativePushPrompt.vue'));
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mocks.appStateCallback = null;
    mocks.initializeNativePush.mockResolvedValue({ receive: 'denied' });
  });

  it('keeps a recovery action visible when Android reports denied', async () => {
    const wrapper = mount(NativePushPrompt);
    await flushPromises();

    expect(wrapper.text()).toContain('Abrir configurações');

    await wrapper.get('button').trigger('click');
    await flushPromises();

    expect(mocks.openNotificationSettings).toHaveBeenCalledWith({
      channelId: undefined,
    });
    expect(mocks.enableNativePush).not.toHaveBeenCalled();
  });

  it('opens the message channel when only that channel is blocked', async () => {
    mocks.initializeNativePush.mockResolvedValueOnce({
      receive: 'denied',
      settingsTarget: 'channel',
      channelId: 'viperchat_messages',
    });
    const wrapper = mount(NativePushPrompt);
    await flushPromises();

    await wrapper.get('button').trigger('click');
    await flushPromises();

    expect(mocks.openNotificationSettings).toHaveBeenCalledWith({
      channelId: 'viperchat_messages',
    });
  });

  it('hides the recovery action after permission is granted in settings', async () => {
    const wrapper = mount(NativePushPrompt);
    await flushPromises();
    mocks.initializeNativePush.mockResolvedValueOnce({
      receive: 'granted',
      registered: true,
    });

    await mocks.appStateCallback({ isActive: true });
    await flushPromises();

    expect(wrapper.find('aside').exists()).toBe(false);
  });
});
