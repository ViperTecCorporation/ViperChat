import { shallowMount } from '@vue/test-utils';
import MobileSidebarLauncher from '../MobileSidebarLauncher.vue';

vi.mock('vue-router', () => ({ useRoute: () => ({ name: 'agent_calls' }) }));

describe('mobile sidebar launcher placement', () => {
  it('sits beside the compact rail or expanded drawer and returns when hidden', async () => {
    const wrapper = shallowMount(MobileSidebarLauncher);
    expect(wrapper.classes()).not.toContain('ltr:translate-x-12');
    await wrapper.setProps({ isMobileSidebarOpen: true });
    expect(wrapper.classes()).toContain('ltr:translate-x-12');
    await wrapper.setProps({ isSidebarExpanded: true });
    expect(wrapper.classes()).toContain('ltr:translate-x-48');
    expect(wrapper.classes()).not.toContain('ltr:translate-x-12');
    await wrapper.setProps({ isMobileSidebarOpen: false });
    expect(wrapper.classes()).not.toContain('ltr:translate-x-48');
    wrapper.unmount();
  });
});
