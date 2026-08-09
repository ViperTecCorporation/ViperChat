import { mount } from '@vue/test-utils';
import SidebarNotificationBell from '../SidebarNotificationBell.vue';

const RouterLinkStub = {
  props: ['to'],
  emits: ['click'],
  template: '<a @click.prevent="$emit(\'click\')"><slot /></a>',
};

const mountBell = props =>
  mount(SidebarNotificationBell, {
    props: {
      label: 'Notificações',
      to: '/app/accounts/1/inbox-view',
      ...props,
    },
    global: {
      stubs: { RouterLink: RouterLinkStub },
    },
  });

describe('SidebarNotificationBell', () => {
  it('shows the label and unread count in the expanded sidebar', () => {
    const wrapper = mountBell({ unreadCount: 7 });

    expect(
      wrapper.find('[data-test-id="sidebar-notifications-label"]').text()
    ).toBe('Notificações');
    expect(
      wrapper.find('[data-test-id="sidebar-notifications-badge"]').text()
    ).toBe('7');
  });

  it('keeps only the bell and capped badge visible when collapsed', () => {
    const wrapper = mountBell({ isCollapsed: true, unreadCount: 120 });

    expect(
      wrapper.find('[data-test-id="sidebar-notifications-label"]').exists()
    ).toBe(false);
    expect(
      wrapper.find('[data-test-id="sidebar-notifications-badge"]').text()
    ).toBe('99+');
  });

  it('does not show a badge without unread notifications', () => {
    const wrapper = mountBell({ unreadCount: 0 });

    expect(
      wrapper.find('[data-test-id="sidebar-notifications-badge"]').exists()
    ).toBe(false);
  });

  it('emits navigate when opened', async () => {
    const wrapper = mountBell();

    await wrapper
      .find('[data-test-id="sidebar-notifications-link"]')
      .trigger('click');

    expect(wrapper.emitted('navigate')).toHaveLength(1);
  });
});
