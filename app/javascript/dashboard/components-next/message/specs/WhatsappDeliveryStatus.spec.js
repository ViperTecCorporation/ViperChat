import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import WhatsappDeliveryStatus from '../WhatsappDeliveryStatus.vue';
import messages from 'dashboard/i18n/locale/pt_BR/conversation.json';

const render = attributes =>
  mount(WhatsappDeliveryStatus, {
    props: { attributes },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
    },
  });

describe('Provider delivery outcomes', () => {
  it('keeps the first failure visible alongside confirmed alternate delivery, without a retry action', () => {
    const wrapper = render({
      whatsapp_delivery: {
        unoapi: { state: 'failed', error: '409: Sessão desconectada' },
        whatsapp_cloud: { state: 'delivered' },
      },
    });
    expect(wrapper.text()).toContain('ViperConnect: Falha no envio');
    expect(wrapper.text()).toContain('409: Sessão desconectada');
    expect(wrapper.text()).toContain('Meta: Entregue');
    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('reacts to websocket updates without a refresh and supports camelized attributes', async () => {
    const wrapper = render({});
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
    await wrapper.setProps({
      attributes: {
        whatsappDelivery: {
          unoapi: { state: 'failed' },
          whatsappCloud: { state: 'progress' },
        },
      },
    });
    expect(wrapper.text()).toContain('Meta: Tentando enviar');
    await wrapper.setProps({
      attributes: {
        whatsappDelivery: {
          unoapi: { state: 'failed' },
          whatsappCloud: { state: 'sent', origin: 'api' },
        },
      },
    });
    expect(wrapper.text()).toContain('Meta: Aceita para envio');
    expect(wrapper.text()).not.toContain('Entregue');
  });

  it('does not present an echo as delivery confirmation', () => {
    const wrapper = render({
      whatsapp_delivery: {
        unoapi: { state: 'failed' },
        whatsapp_cloud: { state: 'sent', origin: 'echo' },
      },
    });
    expect(wrapper.text()).toContain('Meta: Mensagem observada neste canal');
    expect(wrapper.text()).not.toContain('Entregue');
  });

  it('displays both failures and the reason a fallback is blocked as safe text', () => {
    const wrapper = render({
      whatsappDelivery: {
        unoapi: { state: 'failed', error: '<img src=x onerror=alert(1)>' },
        whatsappCloud: { state: 'failed' },
      },
      whatsappTransport: { fallbackBlockedReason: 'template_required' },
    });
    expect(wrapper.text()).toContain('ViperConnect: Falha no envio');
    expect(wrapper.text()).toContain('Meta: Falha no envio');
    expect(wrapper.text()).toContain('modelo aprovado');
    expect(wrapper.find('img').exists()).toBe(false);
  });

  it('does not add noise to a normal single-provider success', () => {
    expect(
      render({ whatsapp_delivery: { unoapi: { state: 'delivered' } } })
        .find('[role="status"]')
        .exists()
    ).toBe(false);
  });
});
