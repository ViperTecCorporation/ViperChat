import { mount } from '@vue/test-utils';
import ConfirmationModal from './ConfirmationModal.vue';

const ModalStub = {
  props: {
    show: { type: Boolean, default: false },
    onClose: { type: Function, default: null },
  },
  template: '<div><slot /></div>',
};

const ButtonStub = {
  props: {
    label: { type: String, default: '' },
  },
  emits: ['click'],
  template: '<button @click="$emit(\'click\')">{{ label }}</button>',
};

const mountComponent = props =>
  mount(ConfirmationModal, {
    props,
    global: {
      stubs: {
        Modal: ModalStub,
        NextButton: ButtonStub,
        WootModalHeader: true,
      },
    },
  });

describe('ConfirmationModal', () => {
  it('uses the labels supplied by the caller', () => {
    const wrapper = mountComponent({
      confirmLabel: 'Sim',
      cancelLabel: 'Não',
    });

    expect(wrapper.findAll('button').map(button => button.text())).toEqual([
      'Não',
      'Sim',
    ]);
  });

  it('confirms with Enter when enabled and visible', async () => {
    const wrapper = mountComponent({ confirmOnEnter: true });
    const confirmation = wrapper.vm.showConfirmation();

    window.dispatchEvent(
      new KeyboardEvent('keydown', {
        key: 'Enter',
        cancelable: true,
      })
    );

    await expect(confirmation).resolves.toBe(true);
    expect(wrapper.vm.show).toBe(false);
  });

  it('does not confirm with Enter unless enabled', async () => {
    const wrapper = mountComponent({ confirmOnEnter: false });
    wrapper.vm.showConfirmation();

    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' }));
    await wrapper.vm.$nextTick();

    expect(wrapper.vm.show).toBe(true);
    wrapper.vm.cancel();
  });
});
