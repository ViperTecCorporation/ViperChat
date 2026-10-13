import { mount } from '@vue/test-utils';
import { ref, nextTick } from 'vue';
import MessageMeta from '../MessageMeta.vue';

const { context } = vi.hoisted(() => ({ context: {} }));
vi.mock('../provider.js', () => ({ useMessageContext: () => context }));
vi.mock('dashboard/composables/useInbox', () => ({
  useInbox: () => ({
    isAWhatsAppChannel: ref(true),
    isAnEmailChannel: ref(false),
  }),
}));

describe('Web attendance message receipts', () => {
  const render = (destination = 'web') => {
    Object.assign(context, {
      status: ref('sent'),
      id: ref(1),
      conversationId: ref(1),
      isPrivate: ref(false),
      createdAt: ref(1791052800),
      sourceId: ref(null),
      deliveryDestination: ref(destination),
      messageType: ref(1),
      contentAttributes: ref({}),
    });
    return mount(MessageMeta, {
      global: {
        stubs: {
          FavoriteIndicator: true,
          Icon: true,
          MessageStatus: {
            props: ['status'],
            template: '<span data-status="true">{{ status }}</span>',
          },
        },
      },
    });
  };

  it.each(['sent', 'delivered', 'read', 'progress'])(
    'shows live Web receipt %s without a WhatsApp source ID',
    async status => {
      const wrapper = render();
      context.status.value = status;
      await nextTick();
      expect(wrapper.find('[data-status]').text()).toBe(status);
    }
  );

  it('preserves the WhatsApp pending indicator without a provider ID', () => {
    expect(render('channel').find('[data-status]').text()).toBe('progress');
  });

  it('does not expose receipts for private, incoming or deleted messages', async () => {
    const wrapper = render();
    context.isPrivate.value = true;
    await nextTick();
    expect(wrapper.find('[data-status]').exists()).toBe(false);
    context.isPrivate.value = false;
    context.messageType.value = 0;
    await nextTick();
    expect(wrapper.find('[data-status]').exists()).toBe(false);
    context.messageType.value = 1;
    context.contentAttributes.value = { deleted: true };
    await nextTick();
    expect(wrapper.find('[data-status]').exists()).toBe(false);
  });
});
