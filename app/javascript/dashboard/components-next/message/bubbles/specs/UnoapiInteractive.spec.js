import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import UnoapiInteractive from '../UnoapiInteractive.vue';

const context = {};
vi.mock('../../provider.js', () => ({ useMessageContext: () => context }));
vi.mock('vuex', () => ({ useStore: () => ({ dispatch: vi.fn() }) }));

describe('UnoAPI order document', () => {
  beforeEach(() => {
    Object.assign(context, {
      content: ref('Pedido com boleto e PIX'),
      id: ref(1),
      conversationId: ref(1),
      contentAttributes: ref({
        whatsappInteractive: {
          type: 'order_details',
          header: { type: 'document', filename: 'boletoTeste.pdf' },
        },
      }),
      attachments: ref([
        {
          id: 9,
          fileType: 'file',
          extension: 'pdf',
          dataUrl: 'https://chat.example.com/stored/boleto.pdf',
        },
      ]),
    });
  });

  it('renders the stored document link together with the order text', () => {
    const wrapper = mount(UnoapiInteractive, {
      global: {
        mocks: { $t: key => key },
        stubs: {
          BaseBubble: { template: '<div><slot /></div>' },
          FileIcon: true,
        },
      },
    });
    expect(wrapper.text()).toContain('Pedido com boleto e PIX');
    expect(wrapper.get('a').text()).toContain('boletoTeste.pdf');
    expect(wrapper.get('a').attributes('href')).toBe(
      'https://chat.example.com/stored/boleto.pdf'
    );
    expect(wrapper.get('a').attributes('rel')).toBe('noopener noreferrer');
  });

  it('keeps the order readable when downloading the PDF failed', () => {
    context.attachments.value = [];
    const wrapper = mount(UnoapiInteractive, {
      global: {
        mocks: { $t: key => key },
        stubs: {
          BaseBubble: { template: '<div><slot /></div>' },
          FileIcon: true,
        },
      },
    });
    expect(wrapper.text()).toContain('Pedido com boleto e PIX');
    expect(wrapper.find('a').exists()).toBe(false);
  });
});
