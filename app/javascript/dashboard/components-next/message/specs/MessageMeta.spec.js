import { mount } from '@vue/test-utils';
import { ref, nextTick } from 'vue';
import MessageMeta from '../MessageMeta.vue';
import {
  buildSnapshot,
  restoreSnapshot,
} from 'dashboard/helper/CacheHelper/frontendSnapshot';

const { context } = vi.hoisted(() => ({ context: {} }));
vi.mock('../provider.js', () => ({ useMessageContext: () => context }));
vi.mock('dashboard/composables/useInbox', () => ({
  useInbox: () => ({
    isAWhatsAppChannel: ref(true),
    isAnEmailChannel: ref(false),
  }),
}));

describe('Web attendance message receipts', () => {
  const render = (destination = 'web', cachedMessage = null) => {
    Object.assign(context, {
      status: ref(cachedMessage?.status || 'sent'),
      id: ref(1),
      conversationId: ref(1),
      isPrivate: ref(false),
      createdAt: ref(1791052800),
      sourceId: ref(cachedMessage?.source_id || null),
      deliveryDestination: ref(destination),
      messageType: ref(1),
      contentAttributes: ref({}),
    });
    return mount(MessageMeta, {
      global: {
        stubs: {
          FavoriteIndicator: true,
          Icon: !cachedMessage,
          MessageStatus: cachedMessage
            ? false
            : {
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

  it.each(['delivered', 'read'])(
    'renders the actual %s icon on the first mount from a restored snapshot, before HTTP',
    status => {
      const state = {
        conversations: {
          selectedChatId: 1,
          allConversations: [
            {
              id: 1,
              account_id: 1,
              meta: {},
              messages: [
                {
                  id: 1,
                  status,
                  source_id: 'synthetic-provider-id',
                  conversation_id: 1,
                  message_type: 1,
                  created_at: 1791052800,
                },
              ],
            },
          ],
        },
        accounts: { records: [] },
        inboxes: { records: [] },
        agents: { records: [] },
        labels: { records: [] },
        teams: { records: {} },
        contacts: { records: {} },
      };
      const snapshot = buildSnapshot(
        state,
        { accountId: 1, key: 'synthetic', permissions: 'synthetic' },
        Date.now()
      );
      restoreSnapshot(state, JSON.parse(JSON.stringify(snapshot)));
      const message = state.conversations.allConversations[0].messages[0];
      const wrapper = render('channel', message);

      expect(wrapper.find('.i-lucide-check-check').exists()).toBe(true);
      expect(wrapper.find('[class*="i-lucide-clock-"]').exists()).toBe(false);
      expect(
        wrapper
          .find('.i-lucide-check-check')
          .classes()
          .includes('text-[#7EB6FF]')
      ).toBe(status === 'read');
      wrapper.unmount();
    }
  );

  it('shows awaiting and cancel for a durable queued message, including private notes', async () => {
    const wrapper = render();
    context.isPrivate.value = true;
    context.contentAttributes.value = {
      offlineQueue: { state: 'waiting', id: 'synthetic' },
    };
    await nextTick();
    expect(wrapper.text()).toContain('Waiting for connection to send');
    expect(wrapper.text()).toContain('Cancel sending');
    expect(wrapper.find('[data-status]').exists()).toBe(false);
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
