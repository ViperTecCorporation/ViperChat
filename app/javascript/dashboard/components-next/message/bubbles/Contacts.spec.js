import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import { createI18n } from 'vue-i18n';
import locale from 'dashboard/i18n/locale/pt_BR/conversation.json';
import Contacts from './Contacts.vue';

const state = vi.hoisted(() => ({
  attachments: null,
  contentAttributes: null,
}));
vi.mock('../provider', () => ({ useMessageContext: () => state }));

describe('shared contacts', () => {
  beforeEach(() => {
    state.attachments = ref([
      {
        id: 1,
        fileType: 'contact',
        fallbackTitle: '+15550101',
        meta: { formattedName: 'Primeiro' },
      },
      {
        id: 2,
        fileType: 'contact',
        fallbackTitle: '',
        meta: { formattedName: 'Segundo', email: 'second@example.com' },
      },
    ]);
    state.contentAttributes = ref({});
  });
  const render = () =>
    mount(Contacts, {
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'pt_BR',
            messages: { pt_BR: locale },
          }),
        ],
        stubs: {
          BaseAttachmentBubble: {
            props: ['title', 'action'],
            template:
              '<div><span>{{ title }}</span><button @click="action.onClick">{{ action.label }}</button></div>',
          },
          Dialog: {
            data: () => ({ visible: false }),
            methods: {
              open() {
                this.visible = true;
              },
            },
            template: '<section v-if="visible"><slot /></section>',
          },
          ContactBubble: {
            props: ['contactAttachment'],
            template:
              '<article>{{ contactAttachment.meta.formattedName }}</article>',
          },
        },
      },
    });

  it('shows one summary, opens all contacts and searches by email', async () => {
    const wrapper = render();
    expect(wrapper.text()).toContain('Primeiro e 1 outro contato');
    expect(wrapper.findAll('article')).toHaveLength(0);
    await wrapper.get('button').trigger('click');
    expect(wrapper.findAll('article')).toHaveLength(2);
    await wrapper.get('input').setValue('second@example.com');
    expect(wrapper.findAll('article')).toHaveLength(1);
    expect(wrapper.get('article').text()).toBe('Segundo');
    await wrapper.get('input').setValue('missing');
    expect(wrapper.text()).toContain('Nenhum contato encontrado');
  });

  it('keeps legacy contacts without attachments visible', async () => {
    state.attachments.value = [];
    state.contentAttributes.value = {
      contacts: [{ formatted_name: 'Antigo' }],
    };
    const wrapper = render();
    expect(wrapper.text()).toContain('Antigo');
    await wrapper.get('button').trigger('click');
    expect(wrapper.findAll('article')).toHaveLength(1);
  });
});
