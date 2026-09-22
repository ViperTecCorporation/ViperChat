import { flushPromises, shallowMount } from '@vue/test-utils';
import Switch from 'next/switch/Switch.vue';
import LastAssigneeAsParticipant from '../LastAssigneeAsParticipant.vue';

const mocks = vi.hoisted(() => ({
  account: null,
  update: vi.fn(),
  alert: vi.fn(),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: mocks.alert }));
vi.mock('dashboard/composables/useAccount', async () => {
  const { ref } = await import('vue');
  mocks.account = ref({ settings: {} });
  return {
    useAccount: () => ({
      currentAccount: mocks.account,
      updateAccount: mocks.update,
    }),
  };
});

describe('last agent participant preference', () => {
  const mount = () =>
    shallowMount(LastAssigneeAsParticipant, {
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
    mocks.account.value = { settings: {} };
    mocks.update.mockResolvedValue();
  });
  it('defaults to true and saves false', async () => {
    const wrapper = mount();
    const control = wrapper.findComponent(Switch);
    expect(control.props('modelValue')).toBe(true);
    control.vm.$emit('update:modelValue', false);
    control.vm.$emit('change');
    await flushPromises();
    expect(mocks.update).toHaveBeenCalledWith({
      last_assignee_as_participant: false,
    });
  });
  it('loads an explicitly disabled preference', () => {
    mocks.account.value = { settings: { last_assignee_as_participant: false } };
    expect(mount().findComponent(Switch).props('modelValue')).toBe(false);
  });
  it('aligns the switch to the end of the header actions like adjacent settings', () => {
    const control = mount().findComponent(Switch);
    expect(
      control.element.parentElement.classList.contains('justify-end')
    ).toBe(true);
    expect(control.element.parentElement.classList.contains('flex')).toBe(true);
  });
  it('rolls back on save failure', async () => {
    mocks.update.mockRejectedValue(new Error('network'));
    const wrapper = mount();
    const control = wrapper.findComponent(Switch);
    control.vm.$emit('update:modelValue', false);
    control.vm.$emit('change');
    await flushPromises();
    expect(control.props('modelValue')).toBe(true);
    expect(mocks.alert).toHaveBeenCalledWith(
      'GENERAL_SETTINGS.FORM.LAST_ASSIGNEE_AS_PARTICIPANT.ERROR'
    );
  });
});
