import { mount } from '@vue/test-utils';
import { defineComponent, h, ref } from 'vue';
import TextBubble from '../Index.vue';
import { provideMessageContext } from '../../../provider';
import { MESSAGE_TYPES } from '../../../constants';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: vi.fn(() => ({ value: [] })),
}));

vi.mock('dashboard/composables/useTranslations', () => ({
  useTranslations: () => ({
    hasTranslations: { value: false },
    translationContent: { value: null },
  }),
}));

const mountTextBubble = ({
  contentAttributes = {},
  content = 'Hello',
} = {}) => {
  const Wrapper = defineComponent({
    setup() {
      provideMessageContext({
        content: ref(content),
        attachments: ref([]),
        contentAttributes: ref(contentAttributes),
        messageType: ref(MESSAGE_TYPES.INCOMING),
      });

      return () => h(TextBubble);
    },
  });

  return mount(Wrapper, {
    global: {
      stubs: {
        BaseBubble: { template: '<div><slot /></div>' },
        FormattedContent: {
          props: ['content'],
          template: '<span>{{ content }}</span>',
        },
        LinkPreviewCard: true,
        AttachmentChips: true,
        TranslationToggle: true,
      },
    },
  });
};

describe('TextBubble', () => {
  it('renders the deleted message notice when deleted content is preserved', () => {
    const wrapper = mountTextBubble({
      contentAttributes: { deleted_content_preserved: true },
    });

    expect(wrapper.text()).toContain('Message deleted');
    expect(wrapper.text()).toContain('Hello');
  });

  it('supports camel case deleted content preserved attributes', () => {
    const wrapper = mountTextBubble({
      contentAttributes: { deletedContentPreserved: true },
    });

    expect(wrapper.text()).toContain('Message deleted');
  });

  it('does not render the deleted message notice for normal messages', () => {
    const wrapper = mountTextBubble();

    expect(wrapper.text()).not.toContain('Message deleted');
  });

  it('renders an incoming WhatsApp referral image inside the text bubble', () => {
    const imageUrl =
      'https://scontent.example.com/campaign.jpg?token=marketing-image';
    const wrapper = mountTextBubble({
      content: `Olá! Tenho interesse.\n\n${imageUrl}`,
      contentAttributes: {
        referral: {
          image_url: { type: 'Buffer', data: [255, 216, 255] },
          thumbnail_url: imageUrl,
        },
      },
    });

    expect(
      wrapper.get('[data-testid="referral-image"]').attributes()
    ).toMatchObject({
      src: imageUrl,
      loading: 'lazy',
      referrerpolicy: 'no-referrer',
    });
    expect(wrapper.text()).toContain('Olá! Tenho interesse.');
    expect(wrapper.text()).not.toContain(imageUrl);
  });
});
