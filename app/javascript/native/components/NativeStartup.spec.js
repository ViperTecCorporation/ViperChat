import { mount } from '@vue/test-utils';
import NativeStartup from './NativeStartup.vue';

describe('native startup connection state', () => {
  it('shows progress and does not retry automatically on failure', async () => {
    vi.useFakeTimers();
    const wrapper = mount(NativeStartup);
    expect(wrapper.find('progress').exists()).toBe(true);
    await wrapper.setProps({ failed: true });
    expect(wrapper.find('progress').exists()).toBe(false);
    expect(wrapper.text()).toContain('Não foi possível conectar');
    await vi.advanceTimersByTimeAsync(60000);
    expect(wrapper.emitted('retry')).toBeUndefined();
    await wrapper.get('button').trigger('click');
    expect(wrapper.emitted('retry')).toHaveLength(1);
    wrapper.unmount();
    vi.useRealTimers();
  });
});
