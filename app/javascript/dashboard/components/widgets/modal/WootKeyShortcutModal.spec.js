import { shallowMount } from '@vue/test-utils';
import WootKeyShortcutModal from './WootKeyShortcutModal.vue';
import NavigationShortcuts from 'dashboard/routes/dashboard/settings/profile/NavigationShortcuts.vue';

vi.mock('dashboard/composables/useDetectKeyboardLayout', () => ({
  useDetectKeyboardLayout: vi.fn().mockResolvedValue('qwerty'),
}));

describe('keyboard shortcut help', () => {
  it('opens the shared profile editor and resets its draft on reopening', async () => {
    const wrapper = shallowMount(WootKeyShortcutModal, {
      props: { show: true },
      global: {
        stubs: { WootModal: { template: '<div><slot /></div>' } },
      },
    });
    expect(wrapper.findComponent(NavigationShortcuts).exists()).toBe(true);
    await wrapper.setProps({ show: false });
    expect(wrapper.findComponent(NavigationShortcuts).exists()).toBe(false);
    await wrapper.setProps({ show: true });
    expect(wrapper.findComponent(NavigationShortcuts).exists()).toBe(true);
    expect(wrapper.html()).not.toContain('min-w-[25rem]');
  });
});
