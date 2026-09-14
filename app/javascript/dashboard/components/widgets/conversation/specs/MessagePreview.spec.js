import { shallowMount } from '@vue/test-utils';
import LegacyPreview from '../MessagePreview.vue';
import NextPreview from 'dashboard/components-next/Conversation/ConversationCard/MessagePreview.vue';

describe.each([LegacyPreview, NextPreview])(
  'media preview renderer',
  Component => {
    it('renders the audio transcription without message content', () => {
      const wrapper = shallowMount(Component, {
        props: {
          message: {
            content: null,
            attachments: [
              {
                file_type: 'audio',
                transcribed_text:
                  'Vou separar tudo aqui e daí eu te mando, tá?',
              },
            ],
          },
        },
      });
      expect(wrapper.text()).toContain(
        'Vou separar tudo aqui e daí eu te mando, tá?'
      );
      expect(wrapper.text()).not.toContain('Nenhum conteúdo');
    });
    it('keeps the configured empty fallback', () => {
      const wrapper = shallowMount(Component, {
        props: {
          message: { content: null, attachments: [] },
          defaultEmptyMessage: 'Empty preview',
        },
      });
      expect(wrapper.text()).toContain('Empty preview');
    });
  }
);
