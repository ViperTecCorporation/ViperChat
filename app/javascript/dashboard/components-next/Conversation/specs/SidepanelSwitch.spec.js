import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import SidepanelSwitch from '../SidepanelSwitch.vue';

const mocks = vi.hoisted(() => ({ inbox: null, chat: null }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key => {
    if (key === 'getSelectedChat') return ref(mocks.chat);
    if (key === 'inboxes/getInbox') return ref(() => mocks.inbox);
    if (key === 'getCurrentAccountId') return ref(1);
    return ref(() => false);
  },
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings: ref({}), updateUISettings: vi.fn() }),
}));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));
vi.mock('dashboard/composables/useConversationSidepanel', () => ({
  useConversationSidepanel: () => ({
    isContactSidebarOpen: ref(false),
    openContactSidebar: vi.fn(),
    closeContactSidebar: vi.fn(),
    toggleContactSidebar: vi.fn(),
  }),
}));

describe('web invitation sidebar entry', () => {
  it.each([
    ['unoapi', false, true, true],
    ['whatsapp_cloud', false, true, true],
    ['whatsapp_cloud', true, true, false],
    ['whatsapp_cloud', false, false, false],
    ['cloud', false, true, false],
    ['default', false, true, false],
  ])(
    'gates provider=%s group=%s enabled=%s',
    (provider, group, enabled, expected) => {
      mocks.inbox = {
        channel_type: 'Channel::Whatsapp',
        provider,
        web_attendance_enabled: enabled,
      };
      mocks.chat = { id: 42, inbox_id: 7, group, can_reply: false };
      const wrapper = mount(SidepanelSwitch, {
        global: {
          mocks: { $t: key => key },
          directives: { tooltip: () => {} },
          stubs: {
            ButtonGroup: { template: '<div><slot /></div>' },
            Button: { template: '<button />' },
            WebAttendanceInvitation: true,
          },
        },
      });
      expect(
        wrapper.find('[aria-label="WEB_ATTENDANCE.INVITE"]').exists()
      ).toBe(expected);
      expect(
        wrapper.findComponent({ name: 'WebAttendanceInvitation' }).exists()
      ).toBe(expected);
      wrapper.unmount();
    }
  );
});
