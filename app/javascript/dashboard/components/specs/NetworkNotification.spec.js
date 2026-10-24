import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { frontendCache } from 'dashboard/helper/CacheHelper/frontendCache';
import NetworkNotification from '../NetworkNotification.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

describe('discreet background connection status', () => {
  let wrapper;
  beforeEach(() => {
    vi.useFakeTimers();
    frontendCache.state.validatingSession = false;
  });
  afterEach(() => {
    wrapper?.unmount();
    vi.useRealTimers();
    vi.restoreAllMocks();
  });
  it('never shows the old reconnection/success banner and suppresses short reconnect flashes', async () => {
    wrapper = mount(NetworkNotification, {
      global: {
        plugins: [
          createStore({ state: { conversations: { allConversations: [] } } }),
        ],
      },
    });
    emitter.emit(BUS_EVENTS.WEBSOCKET_RECONNECT);
    await vi.advanceTimersByTimeAsync(500);
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
    await vi.advanceTimersByTimeAsync(701);
    expect(wrapper.text()).toContain('NETWORK.NOTIFICATION.RECONNECTING');
    expect(wrapper.find('[role="status"]').attributes('class')).toContain(
      'bottom-['
    );
    expect(wrapper.find('[role="status"]').attributes('class')).not.toContain(
      'top-['
    );
    expect(wrapper.find('button').exists()).toBe(false);
    emitter.emit(BUS_EVENTS.WEBSOCKET_RECONNECT_COMPLETED);
    await wrapper.vm.$nextTick();
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
  });
  it('identifies offline cached content without blocking the screen or offering reload', async () => {
    vi.spyOn(window.navigator, 'onLine', 'get').mockReturnValue(false);
    wrapper = mount(NetworkNotification, {
      global: {
        plugins: [
          createStore({
            state: {
              conversations: {
                allConversations: [{ id: 1, isCachedSnapshot: true }],
              },
            },
          }),
        ],
      },
    });
    await wrapper.vm.$nextTick();
    expect(wrapper.text()).toContain('NETWORK.NOTIFICATION.SAVED_OFFLINE');
    expect(wrapper.find('[role="status"]').classes()).toContain(
      'pointer-events-none'
    );
    expect(wrapper.find('button').exists()).toBe(false);
  });
});
