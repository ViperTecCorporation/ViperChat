import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import Message from '../Message.vue';
import { ATTACHMENT_TYPES, MESSAGE_STATUS, MESSAGE_TYPES } from '../constants';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key =>
      key === 'GENERAL_SETTINGS.FORM.DELETED_MESSAGE_CONTENT.NOTICE'
        ? 'Message deleted'
        : key,
  }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ query: {} }),
}));

vi.mock('vuex', () => ({
  mapGetters: () => ({}),
  useStore: () => ({
    getters: {
      getCurrentRole: 'administrator',
      getCurrentAccountId: 1,
      'accounts/isFeatureEnabledonAccount': vi.fn(() => false),
    },
  }),
}));

vi.mock('dashboard/composables', () => ({
  useTrack: vi.fn(),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: vi.fn(getter => {
    if (getter === 'inboxes/getInbox') {
      return { value: vi.fn(() => ({})) };
    }

    return { value: [] };
  }),
}));

vi.mock('dashboard/composables/useTranslations', () => ({
  useTranslations: () => ({
    hasTranslations: { value: false },
    translationContent: { value: null },
  }),
}));

vi.mock('dashboard/composables/useInbox', () => ({
  useInbox: () => ({
    isAnInternalChannel: ref(false),
    isAWhatsAppChannel: ref(true),
    isATwilioWhatsAppChannel: ref(false),
  }),
}));

vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({
    replaceInstallationName: text => text,
  }),
}));

vi.mock('../bubbles/Text/FormattedContent.vue', () => ({
  default: {
    name: 'FormattedContent',
    props: ['content'],
    template: '<span>{{ content }}</span>',
  },
}));

vi.mock('../bubbles/Text/LinkPreviewCard.vue', () => ({
  default: {
    name: 'LinkPreviewCard',
    template: '<div />',
  },
}));

vi.mock('next/message/chips/AttachmentChips.vue', () => ({
  default: {
    name: 'AttachmentChips',
    template: '<div />',
  },
}));

vi.mock('dashboard/components-next/message/TranslationToggle.vue', () => ({
  default: {
    name: 'TranslationToggle',
    template: '<button />',
  },
}));

vi.mock('../bubbles/Image.vue', () => ({
  default: {
    name: 'ImageBubble',
    template: '<div data-testid="image-bubble">image bubble</div>',
  },
}));

const defaultProps = {
  id: 1,
  messageType: MESSAGE_TYPES.INCOMING,
  status: MESSAGE_STATUS.SENT,
  content: '',
  attachments: [],
  contentAttributes: {},
  conversationId: 1,
  createdAt: 1710000000,
  currentUserId: 1,
  inboxId: 1,
  inboxSupportsReplyTo: { outgoing: true },
};

const imageAttachment = {
  id: 1,
  fileType: ATTACHMENT_TYPES.IMAGE,
  dataUrl: 'https://example.com/image.png',
  thumbUrl: 'https://example.com/image-thumb.png',
};

const mountMessage = props =>
  mount(Message, {
    props: { ...defaultProps, ...props },
    global: {
      stubs: {
        Avatar: true,
        BaseBubble: {
          template: '<div v-bind="$attrs"><slot /></div>',
        },
        FormattedContent: {
          props: ['content'],
          template: '<span>{{ content }}</span>',
        },
        LinkPreviewCard: true,
        AttachmentChips: true,
        TranslationToggle: true,
        MessageError: true,
        ContextMenu: true,
      },
    },
  });

describe('Message', () => {
  it('renders a deleted placeholder instead of an image bubble for deleted media messages', () => {
    const wrapper = mountMessage({
      attachments: [imageAttachment],
      contentAttributes: { deleted: true },
    });

    expect(wrapper.text()).toContain('Message deleted');
    expect(wrapper.find('[data-bubble-name="text"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="image-bubble"]').exists()).toBe(false);
  });

  it('keeps media visible and marks it when deleted content is preserved', () => {
    const wrapper = mountMessage({
      attachments: [imageAttachment],
      contentAttributes: {
        deleted: true,
        deleted_content_preserved: true,
      },
    });

    expect(wrapper.find('[data-testid="image-bubble"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('Message deleted');
  });
});
