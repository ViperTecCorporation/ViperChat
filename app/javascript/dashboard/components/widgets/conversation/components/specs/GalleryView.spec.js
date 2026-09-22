import { shallowMount } from '@vue/test-utils';
import GalleryView from '../GalleryView.vue';

vi.mock('dashboard/composables/store', () => ({
  useStoreGetters: () => ({ getCurrentUser: { value: { id: 99 } } }),
}));
const { keyboard } = vi.hoisted(() => ({ keyboard: {} }));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: events => Object.assign(keyboard, events),
}));

const attachments = [3, 2, 1].map(id => ({
  id,
  message_id: 10,
  created_at: 1700000000 + id,
  file_type: 'image',
  data_url: `/photo-${id}.png`,
}));
const createWrapper = () =>
  shallowMount(GalleryView, {
    props: {
      show: true,
      attachment: attachments[1],
      allAttachments: attachments,
    },
    global: {
      directives: { 'dompurify-html': () => {} },
      renderStubDefaultSlot: true,
      stubs: {
        'woot-modal': { template: '<div><slot /></div>' },
        NextButton: {
          props: ['icon', 'label', 'disabled'],
          template:
            '<button :data-icon="icon" :disabled="disabled">{{ label }}</button>',
        },
      },
    },
  });

describe('GalleryView', () => {
  it('moves right to newer media and left to older media without changing the grid', async () => {
    const wrapper = createWrapper();
    await wrapper.vm.$nextTick();
    expect(wrapper.find('img').attributes('src')).toBe('/photo-2.png');
    await wrapper
      .find('[data-icon^="ltr:i-lucide-chevron-right"]')
      .trigger('click');
    await wrapper.vm.$nextTick();
    expect(wrapper.find('img').attributes('src')).toBe('/photo-3.png');
    keyboard.ArrowLeft.action();
    await wrapper.vm.$nextTick();
    expect(wrapper.find('img').attributes('src')).toBe('/photo-2.png');
    keyboard.ArrowLeft.action();
    await wrapper.vm.$nextTick();
    expect(wrapper.find('img').attributes('src')).toBe('/photo-1.png');
    expect(attachments.map(item => item.id)).toEqual([3, 2, 1]);
    wrapper.unmount();
  });

  it('provides a labeled close control and does not close when touching the image area', async () => {
    const wrapper = createWrapper();
    await wrapper.vm.$nextTick();
    await wrapper.find('main').trigger('click');
    expect(wrapper.emitted('close')).toBeUndefined();
    const close = wrapper.find('[data-icon="i-lucide-x"]');
    expect(close.text()).toBeTruthy();
    await close.trigger('click');
    expect(wrapper.emitted('close')).toHaveLength(1);
    wrapper.unmount();
  });
});
