import { flushPromises, shallowMount } from '@vue/test-utils';
import Switch from 'next/switch/Switch.vue';
import TeamConversationsInMine from '../TeamConversationsInMine.vue';

const mocks = vi.hoisted(() => ({
  currentAccount: null,
  updateAccount: vi.fn(),
  useAlert: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: mocks.useAlert,
}));

vi.mock('dashboard/composables/useAccount', async () => {
  const { ref } = await import('vue');
  mocks.currentAccount = ref({ settings: {} });

  return {
    useAccount: () => ({
      currentAccount: mocks.currentAccount,
      updateAccount: mocks.updateAccount,
    }),
  };
});

describe('TeamConversationsInMine', () => {
  const mountComponent = () =>
    shallowMount(TeamConversationsInMine, {
      global: {
        stubs: {
          SectionLayout: {
            template: '<section><slot name="headerActions" /></section>',
          },
        },
      },
    });

  beforeEach(() => {
    vi.clearAllMocks();
    mocks.currentAccount.value = { settings: {} };
    mocks.updateAccount.mockResolvedValue();
  });

  it('keeps team conversations enabled by default and persists the disabled preference', async () => {
    const wrapper = mountComponent();
    const switchControl = wrapper.findComponent(Switch);

    expect(switchControl.props('modelValue')).toBe(true);

    switchControl.vm.$emit('update:modelValue', false);
    switchControl.vm.$emit('change');
    await flushPromises();

    expect(mocks.updateAccount).toHaveBeenCalledWith({
      include_team_conversations_in_mine: false,
    });
  });

  it('reflects an account with team conversations disabled', async () => {
    mocks.currentAccount.value = {
      settings: { include_team_conversations_in_mine: false },
    };

    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.findComponent(Switch).props('modelValue')).toBe(false);
  });
});
