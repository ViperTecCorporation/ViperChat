import { mount } from '@vue/test-utils';
import { defineComponent } from 'vue';
import AvatarPreview from './AvatarPreview.vue';

const open = vi.fn();
const close = vi.fn();
const DialogStub = defineComponent({
  setup(_, { expose }) {
    expose({ open, close });
  },
  template: '<section><slot /></section>',
});
const createWrapper = (src = '/avatar.png') =>
  mount(AvatarPreview, {
    props: { src, name: 'Jane Doe' },
    global: { stubs: { Dialog: DialogStub } },
  });

describe('AvatarPreview', () => {
  beforeEach(() => vi.clearAllMocks());

  it('opens the photo without propagating the click to the conversation', async () => {
    const wrapper = createWrapper();
    const parentClick = vi.fn();
    const parent = document.createElement('div');
    parent.appendChild(wrapper.element);
    parent.addEventListener('click', parentClick);
    await wrapper.find('button').trigger('click');
    expect(open).toHaveBeenCalledOnce();
    expect(parentClick).not.toHaveBeenCalled();
    expect(wrapper.find('img').attributes('src')).toBe('/avatar.png');
    wrapper.unmount();
  });

  it('disables opening when no photo exists', () => {
    const wrapper = createWrapper('');
    expect(wrapper.find('button').element.disabled).toBe(true);
    wrapper.unmount();
  });

  it('shows a fallback for an unavailable photo and retries when reopened', async () => {
    const wrapper = createWrapper();
    await wrapper.find('img').trigger('error');
    expect(wrapper.find('[role="status"]').exists()).toBe(true);
    await wrapper.find('button').trigger('click');
    expect(wrapper.find('img').exists()).toBe(true);
    wrapper.unmount();
  });

  it('closes the preview when the photo changes', async () => {
    const wrapper = createWrapper();
    await wrapper.setProps({ src: '/other.png' });
    expect(close).toHaveBeenCalledOnce();
    wrapper.unmount();
  });
});
