import { ref } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import Switch from 'next/switch/Switch.vue';
import AgentLabelCreation from '../AgentLabelCreation.vue';

const mocks = vi.hoisted(() => ({
  account: null,
  update: vi.fn(),
  alert: vi.fn(),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: mocks.alert }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: mocks.account,
    updateAccount: mocks.update,
  }),
}));

describe('Agent label creation setting', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.account = ref({ settings: {} });
    mocks.update.mockResolvedValue();
  });

  it('is disabled by default and persists an explicit opt-in', async () => {
    const wrapper = shallowMount(AgentLabelCreation, {
      global: {
        stubs: {
          SectionLayout: {
            template: '<div><slot name="headerActions" /></div>',
          },
        },
      },
    });
    const toggle = wrapper.findComponent(Switch);
    expect(toggle.props('modelValue')).toBe(false);
    toggle.vm.$emit('update:modelValue', true);
    toggle.vm.$emit('change');
    await flushPromises();
    expect(mocks.update).toHaveBeenCalledWith({
      allow_agents_to_create_labels: true,
    });
  });

  it('restores the saved setting when saving fails', async () => {
    mocks.update.mockRejectedValue(new Error('synthetic failure'));
    const wrapper = shallowMount(AgentLabelCreation, {
      global: {
        stubs: {
          SectionLayout: {
            template: '<div><slot name="headerActions" /></div>',
          },
        },
      },
    });
    const toggle = wrapper.findComponent(Switch);
    toggle.vm.$emit('update:modelValue', true);
    toggle.vm.$emit('change');
    await flushPromises();
    expect(toggle.props('modelValue')).toBe(false);
    expect(mocks.alert).toHaveBeenCalledWith(
      'GENERAL_SETTINGS.FORM.AGENT_LABEL_CREATION.ERROR'
    );
  });
});
