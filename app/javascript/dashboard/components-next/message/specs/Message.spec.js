import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import Message from '../Message.vue';
import {
  ATTACHMENT_TYPES,
  CONTENT_TYPES,
  MESSAGE_STATUS,
  MESSAGE_TYPES,
} from '../constants';

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

  it('renders carousel cards with images, descriptions, and safe actions', () => {
    const wrapper = mountMessage({
      content: 'Confira as últimas ofertas!',
      contentType: CONTENT_TYPES.CARDS,
      contentAttributes: {
        items: [
          {
            title: '',
            description: 'Sistema de automação comercial #1',
            mediaUrl: 'https://example.com/one.jpg',
            actions: [
              {
                type: 'link',
                text: 'Agende uma demonstração',
                uri: 'https://vipertec.com.br/oferta',
              },
            ],
          },
          {
            title: 'Segurança',
            description: 'Segurança a um palmo de sua mão. #2',
            mediaUrl: 'https://example.com/two.jpg',
            actions: [
              {
                type: 'postback',
                text: 'Tenho interesse',
                payload: 'interested',
              },
            ],
          },
        ],
      },
    });

    expect(wrapper.text()).toContain('Confira as últimas ofertas!');
    expect(wrapper.findAll('[data-testid="carousel-card"]')).toHaveLength(2);
    expect(wrapper.findAll('img')).toHaveLength(2);
    expect(wrapper.text()).toContain('Sistema de automação comercial #1');
    expect(wrapper.text()).toContain('Segurança a um palmo de sua mão. #2');
    expect(wrapper.get('a').attributes()).toMatchObject({
      href: 'https://vipertec.com.br/oferta',
      target: '_blank',
      rel: 'noopener noreferrer',
    });
    expect(wrapper.get('button[disabled]').text()).toBe('Tenho interesse');
  });

  it('renders cards without optional images or actions', () => {
    const wrapper = mountMessage({
      content: 'Oferta sem mídia',
      contentType: CONTENT_TYPES.CARDS,
      contentAttributes: {
        items: [{ description: 'Somente descrição' }],
      },
    });

    expect(wrapper.find('[data-testid="carousel-card"]').exists()).toBe(true);
    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.text()).toContain('Somente descrição');
  });

  it('does not crash on malformed card content', () => {
    const wrapper = mountMessage({
      content: 'Conteúdo preservado',
      contentType: CONTENT_TYPES.CARDS,
      contentAttributes: {
        items: [null, 'invalid', { title: 123, actions: 'invalid' }],
      },
    });

    expect(wrapper.text()).toContain('Conteúdo preservado');
    expect(wrapper.findAll('[data-testid="carousel-card"]')).toHaveLength(1);
  });

  it('uses a fallback when a carousel image fails', async () => {
    const wrapper = mountMessage({
      contentType: CONTENT_TYPES.CARDS,
      contentAttributes: {
        items: [{ mediaUrl: 'https://example.com/broken.jpg' }],
      },
    });

    await wrapper.get('img').trigger('error');

    expect(
      wrapper.find('[data-testid="carousel-image-fallback"]').exists()
    ).toBe(true);
  });
});
