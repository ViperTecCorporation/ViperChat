import { flushPromises, mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import PushNotificationBanner from './PushNotificationBanner.vue';
import { requestPushPermissions } from 'dashboard/helper/pushHelper';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/helper/pushHelper', () => ({
  requestPushPermissions: vi.fn(({ onSuccess }) => onSuccess()),
}));

const mountComponent = () =>
  mount(PushNotificationBanner, {
    props: { accountId: 16 },
    global: {
      mocks: { $t: key => key },
    },
  });

describe('PushNotificationBanner', () => {
  beforeEach(() => {
    window.sessionStorage.clear();
    Object.defineProperty(window, 'chatwootConfig', {
      configurable: true,
      value: { vapidPublicKey: 'test-key' },
    });
    Object.defineProperty(window, 'PushManager', {
      configurable: true,
      value: class PushManager {},
    });
    Object.defineProperty(window, 'Notification', {
      configurable: true,
      value: {
        permission: 'granted',
        requestPermission: vi.fn(async () => {
          window.Notification.permission = 'granted';
          return 'granted';
        }),
      },
    });
    Object.defineProperty(navigator, 'serviceWorker', {
      configurable: true,
      value: {
        ready: Promise.resolve({
          pushManager: {
            getSubscription: vi.fn().mockResolvedValue(null),
          },
        }),
      },
    });
  });

  afterEach(() => {
    delete window.PushManager;
    delete window.Notification;
    delete window.chatwootConfig;
    vi.clearAllMocks();
  });

  it('shows the warning while browser notifications are not granted', async () => {
    const wrapper = mountComponent();
    await nextTick();
    await flushPromises();

    expect(wrapper.text()).toContain('CHAT_LIST.PUSH_NOTIFICATIONS.DISABLED');
  });

  it('dismisses the warning for the current browser session', async () => {
    const wrapper = mountComponent();
    await nextTick();
    await flushPromises();

    await wrapper
      .get('[aria-label="CHAT_LIST.PUSH_NOTIFICATIONS.CLOSE"]')
      .trigger('click');

    expect(wrapper.find('[role="status"]').exists()).toBe(false);
    expect(
      window.sessionStorage.getItem('push-notification-banner-dismissed-16')
    ).toBe('true');
  });

  it('requests permission and registers browser push when activated', async () => {
    const wrapper = mountComponent();
    await nextTick();
    await flushPromises();

    await wrapper
      .findAll('button')
      .find(button =>
        button.text().includes('CHAT_LIST.PUSH_NOTIFICATIONS.ACTIVATE')
      )
      .trigger('click');
    await vi.waitFor(() => expect(requestPushPermissions).toHaveBeenCalled());

    expect(Notification.requestPermission).not.toHaveBeenCalled();
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
  });
});
