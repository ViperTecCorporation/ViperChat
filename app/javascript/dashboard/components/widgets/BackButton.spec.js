import { mount } from '@vue/test-utils';
import router from '../../routes/index';
import BackButton from './BackButton.vue';

vi.mock('../../routes/index', () => ({
  default: {
    push: vi.fn(),
    go: vi.fn(),
  },
}));

const mountComponent = props =>
  mount(BackButton, {
    props,
    global: {
      mocks: {
        $t: key => key,
      },
    },
  });

describe('BackButton', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('shows the previous-list count as a mobile badge', () => {
    const wrapper = mountComponent({
      mobileIconOnly: true,
      badgeCount: 12,
      accessibleLabel: 'Minhas',
    });

    expect(wrapper.text()).toContain('12');
    expect(wrapper.attributes('aria-label')).toBe('Minhas (12)');
    expect(wrapper.find('span.hidden.sm\\:inline').text()).toBe(
      'GENERAL_SETTINGS.BACK'
    );
  });

  it('caps large badge values', () => {
    const wrapper = mountComponent({ iconOnly: true, badgeCount: 120 });

    expect(wrapper.text()).toContain('99+');
  });

  it('returns to the provided list URL', async () => {
    const wrapper = mountComponent({ backUrl: '/app/accounts/1/dashboard' });

    await wrapper.trigger('click');

    expect(router.push).toHaveBeenCalledWith('/app/accounts/1/dashboard');
  });
});
