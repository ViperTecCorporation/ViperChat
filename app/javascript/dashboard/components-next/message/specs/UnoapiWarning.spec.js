import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import UnoapiWarning from '../UnoapiWarning.vue';
import messages from 'dashboard/i18n/locale/pt_BR/conversation.json';

const render = contentAttributes =>
  mount(UnoapiWarning, {
    props: { contentAttributes },
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

describe('UnoAPI sending notice', () => {
  it('does not render without warnings', () => {
    expect(render({}).find('details').exists()).toBe(false);
  });

  it('uses the code for the translated notice and supports reloaded attributes', () => {
    const attrs = {
      unoapiWarnings: [
        { code: 'REPLY_SENT_WITHOUT_QUOTE', message: 'English text' },
      ],
    };
    const wrapper = render(attrs);
    expect(wrapper.text()).toContain('Enviada sem citação.');
    expect(wrapper.get('summary').attributes('title')).toContain('WhatsApp');
    expect(wrapper.find('button').exists()).toBe(false);
    wrapper.unmount();
    expect(render(JSON.parse(JSON.stringify(attrs))).text()).toContain(
      'Enviada sem citação.'
    );
  });

  it('renders unknown warnings as text, never executable markup', () => {
    const payload = '<img src=x onerror=alert(1)>';
    const wrapper = render({
      unoapi_warnings: [{ code: 'NEW_CODE', message: payload }],
    });
    expect(wrapper.text()).toContain(payload);
    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.find('script').exists()).toBe(false);
  });
});
