import { mount } from '@vue/test-utils';
import { defineComponent, h, ref } from 'vue';
import BaseAttachment from '../BaseAttachment.vue';
import { provideMessageContext } from '../../provider.js';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref([]),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const mountAttachment = () => {
  const Wrapper = defineComponent({
    setup() {
      provideMessageContext({ sender: ref({ name: 'Agent' }) });
      return () =>
        h(BaseAttachment, {
          icon: 'i-lucide-file',
          senderTranslationKey: 'CONVERSATION.SHARED_ATTACHMENT.FILE',
          content: 'very-long-file-name.pdf',
          action: { href: '/file.pdf', label: 'Baixar' },
        });
    },
  });

  return mount(Wrapper, {
    global: {
      stubs: {
        BaseBubble: { template: '<div><slot /></div>' },
        Icon: true,
      },
    },
  });
};

describe('BaseAttachment', () => {
  it('keeps its download action within the available bubble width', () => {
    const wrapper = mountAttachment();
    const action = wrapper.get('a');

    expect(wrapper.html()).not.toContain('min-w-64');
    expect(action.classes()).toEqual(
      expect.arrayContaining(['w-full', 'max-w-full', 'box-border'])
    );
  });
});
