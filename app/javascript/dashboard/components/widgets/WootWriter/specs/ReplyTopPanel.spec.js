import { mount } from '@vue/test-utils';
import ReplyTopPanel from '../ReplyTopPanel.vue';

vi.mock('dashboard/composables/useCaptain', () => ({
  useCaptain: () => ({ captainTasksEnabled: { value: true } }),
}));

vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));

const ButtonStub = {
  props: {
    icon: { type: String, default: '' },
    disabled: { type: Boolean, default: false },
  },
  emits: ['click'],
  template: `<button
    :data-icon="icon"
    :disabled="disabled"
    @click="$emit('click')"
  />`,
};

const mountComponent = props =>
  mount(ReplyTopPanel, {
    props,
    global: {
      mocks: { $t: key => key },
      stubs: {
        NextButton: ButtonStub,
        EditorModeToggle: true,
        CopilotMenuBar: true,
      },
    },
  });

describe('ReplyTopPanel', () => {
  it('shows the PIX action immediately before the Captain action', () => {
    const wrapper = mountComponent({ showPixButton: true });
    const icons = wrapper
      .findAll('button')
      .map(button => button.attributes('data-icon'));

    expect(icons).toEqual([
      'i-lucide-qr-code',
      'i-ph-sparkle-fill',
      'i-lucide-maximize-2',
    ]);
  });

  it('emits the PIX payment action when clicked', async () => {
    const wrapper = mountComponent({ showPixButton: true });

    await wrapper.find('[data-icon="i-lucide-qr-code"]').trigger('click');

    expect(wrapper.emitted('sendPixPayment')).toHaveLength(1);
  });

  it('hides the PIX action when the inbox has no configuration', () => {
    const wrapper = mountComponent({ showPixButton: false });

    expect(wrapper.find('[data-icon="i-lucide-qr-code"]').exists()).toBe(false);
  });
});
