import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import Message from '../Message.vue';
import Attachment from '../Attachment.vue';
import messages from '../i18n';

const global = {
  plugins: [createI18n({ legacy: false, locale: 'pt-BR', messages })],
};

describe('visitor message rendering', () => {
  it.each(['image', 'audio', 'video', 'file'])(
    'renders an operator %s on the team side with the operator name',
    fileType => {
      const wrapper = mount(Message, {
        props: {
          message: {
            id: 20,
            message_type: 1,
            created_at: 1,
            sender: { name: 'Operator' },
            attachments: [
              {
                id: 20,
                file_type: fileType,
                url: '/web-attendance/api/attachments/20',
              },
            ],
          },
        },
        global,
      });
      expect(wrapper.get('article').classes()).toContain('justify-start');
      expect(wrapper.text()).toContain('Operator');
      wrapper.unmount();
    }
  );
  it('renders an accepted audio bubble at a usable width with its sent receipt', () => {
    const wrapper = mount(Message, {
      props: {
        message: {
          id: 6,
          message_type: 0,
          created_at: 1,
          status: 'sent',
          attachments: [
            {
              id: 8,
              file_type: 'audio',
              url: '/web-attendance/api/attachments/8',
            },
          ],
        },
      },
      global,
    });
    expect(wrapper.get('article > div').classes()).toContain('w-80');
    expect(wrapper.get('audio').attributes('src')).toBe(
      '/web-attendance/api/attachments/8'
    );
    expect(wrapper.get('[role="img"]').attributes('aria-label')).toBe(
      'Enviada'
    );
    wrapper.unmount();
  });
  it.each([0, 1])(
    'updates receipt states on message side %s',
    async messageType => {
      const message = { id: 1, message_type: messageType, created_at: 1 };
      const wrapper = mount(Message, { props: { message }, global });
      expect(wrapper.find('[role="img"]').exists()).toBe(false);
      await [
        ['sent', 'Enviada', '✓'],
        ['delivered', 'Entregue', '✓✓'],
        ['read', 'Lida', '✓✓'],
      ].reduce(async (previous, [status, label, icon]) => {
        await previous;
        await wrapper.setProps({ message: { ...message, status } });
        const receipt = wrapper.get('[role="img"]');
        expect(receipt.text()).toBe(icon);
        expect(receipt.attributes('aria-label')).toBe(label);
        expect(receipt.attributes('title')).toBe(label);
        expect(receipt.classes().includes('text-n-blue-11')).toBe(
          status === 'read'
        );
        expect(receipt.get('span').attributes('aria-hidden')).toBe('true');
      }, Promise.resolve());
      await wrapper.setProps({ message: { ...message, status: 'progress' } });
      expect(wrapper.find('[role="img"]').exists()).toBe(false);
      wrapper.unmount();
    }
  );

  it.each([
    ['sent', 'Sent'],
    ['delivered', 'Delivered'],
    ['read', 'Read'],
  ])('translates the %s receipt tooltip into English', (status, label) => {
    const wrapper = mount(Message, {
      props: { message: { id: 1, message_type: 0, created_at: 1, status } },
      global: {
        plugins: [createI18n({ legacy: false, locale: 'en', messages })],
      },
    });
    expect(wrapper.get('[role="img"]').attributes('title')).toBe(label);
    expect(wrapper.get('[role="img"]').attributes('aria-label')).toBe(label);
    wrapper.unmount();
  });

  it('does not mount view-once media before opening and allows replay', async () => {
    const wrapper = mount(Message, {
      props: {
        message: {
          id: 1,
          message_type: 1,
          created_at: 1,
          view_once: true,
          content: 'Hidden',
          attachments: [
            {
              id: 1,
              file_type: 'audio',
              url: '/web-attendance/api/attachments/1',
            },
          ],
        },
      },
      global,
    });
    expect(wrapper.find('audio').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('Hidden');
    await wrapper.find('button').trigger('click');
    expect(wrapper.find('audio').attributes('src')).toBe(
      '/web-attendance/api/attachments/1'
    );
    expect(wrapper.find('audio').attributes()).not.toHaveProperty('autoplay');
    await wrapper.find('audio').trigger('ended');
    expect(wrapper.find('audio').exists()).toBe(true);
    wrapper.unmount();
  });

  it('renders message content as text without executing HTML', () => {
    const wrapper = mount(Message, {
      props: {
        message: {
          id: 1,
          created_at: 1,
          content: '<img src=x onerror=alert(1)>',
        },
      },
      global,
    });
    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.text()).toContain('<img src=x onerror=alert(1)>');
    wrapper.unmount();
  });

  it('shows stored contact metadata and phone number', () => {
    const wrapper = mount(Attachment, {
      props: {
        attachment: {
          file_type: 'contact',
          fallback_title: '+556612345678',
          meta: {
            formattedName: 'Example contact',
            email: 'contact@example.test',
          },
        },
      },
      global,
    });
    expect(wrapper.text()).toContain('Example contact');
    expect(wrapper.text()).toContain('+556612345678');
    expect(wrapper.text()).toContain('contact@example.test');
    wrapper.unmount();
  });

  it.each(['image', 'audio', 'video', 'file'])(
    'does not render %s with default zero coordinates as a location',
    fileType => {
      const wrapper = mount(Attachment, {
        props: {
          attachment: {
            file_type: fileType,
            latitude: 0,
            longitude: 0,
            url: '/web-attendance/api/attachments/9',
            name: 'Uploaded media',
          },
        },
        global,
      });
      expect(wrapper.find('a[href*="openstreetmap"]').exists()).toBe(false);
      if (fileType === 'image') {
        expect(wrapper.get('img').attributes('src')).toBe(
          '/web-attendance/api/attachments/9'
        );
      }
      if (fileType === 'audio')
        expect(wrapper.find('audio').exists()).toBe(true);
      if (fileType === 'video')
        expect(wrapper.find('video').exists()).toBe(true);
      if (fileType === 'file') {
        expect(wrapper.get('a').attributes('href')).toBe(
          '/web-attendance/api/attachments/9'
        );
      }
      wrapper.unmount();
    }
  );

  it('renders valid zero coordinates as a safe map link', () => {
    const wrapper = mount(Attachment, {
      props: {
        attachment: { file_type: 'location', latitude: 0, longitude: 0 },
      },
      global,
    });
    expect(wrapper.find('a').attributes('href')).toBe(
      'https://www.openstreetmap.org/?mlat=0&mlon=0#map=16/0/0'
    );
    wrapper.unmount();
  });
});
