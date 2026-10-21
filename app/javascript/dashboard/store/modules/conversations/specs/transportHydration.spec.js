import { computed, nextTick, reactive } from 'vue';
import { mount } from '@vue/test-utils';
import actions from '../actions';
import { mutations } from '../index';
import ConversationApi from 'dashboard/api/inbox/conversation';
import { useWhatsappTransport } from 'dashboard/composables/useWhatsappTransport';
import WhatsappTransportSelector from 'dashboard/components/widgets/WootWriter/WhatsappTransportSelector.vue';
import ReplyBox from 'dashboard/components/widgets/conversation/ReplyBox.vue';
import types from '../../../mutation-types';

vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { show: vi.fn() },
}));

const options = {
  link_id: 3,
  default_provider: 'unoapi',
  transports: [
    { provider: 'unoapi', label: 'ViperConnect', inbox_id: 1, can_reply: true },
    { provider: 'whatsapp_cloud', label: 'Meta', inbox_id: 2, can_reply: true },
  ],
};

describe('transport detail hydration on conversation activation', () => {
  it.each(['compact', 'full'])(
    'shows the selector in %s without reload and preserves the operator choice across refreshes',
    async layout => {
      const chat = {
        id: 61,
        account_id: 1,
        updated_at: 200,
        meta: { channel: 'Channel::Whatsapp' },
        dataFetched: true,
        messages: [],
      };
      const state = reactive({ allConversations: [chat], selectedChatId: 61 });
      const selected = computed(() => state.allConversations[0]);
      const transport = useWhatsappTransport(selected, `hydration-${layout}`);
      const wrapper = mount({
        components: { WhatsappTransportSelector },
        setup: () => ({
          options: transport.options,
          provider: transport.selectedProvider,
          visible: computed(() =>
            ReplyBox.computed.showWhatsappTransportSelector.call({
              whatsappTransportOptions: transport.options.value,
              useCompactMessageComposer: layout === 'compact',
              isWebDestination: false,
              isOnPrivateNote: false,
            })
          ),
        }),
        template:
          '<WhatsappTransportSelector v-if="visible" v-model="provider" :transports="options.transports" />',
      });
      expect(wrapper.find('select').exists()).toBe(false);
      const commit = (type, payload) => mutations[type](state, payload);
      const dispatch = vi.fn((type, id) => actions[type]({ commit }, id));
      ConversationApi.show.mockResolvedValue({
        data: {
          id: 61,
          account_id: 1,
          updated_at: 100,
          whatsapp_transport_options: options,
        },
      });
      await actions.setActiveChat({ commit, dispatch }, { data: chat });
      await nextTick();
      expect(dispatch).toHaveBeenCalledWith('refreshWhatsappTransport', 61);
      expect(wrapper.get('select').element.value).toBe('unoapi');
      await wrapper.get('select').setValue('whatsapp_cloud');
      await actions.setActiveChat(
        { commit, dispatch },
        { data: selected.value }
      );
      await nextTick();
      expect(wrapper.get('select').element.value).toBe('whatsapp_cloud');
      expect(selected.value.updated_at).toBe(200);
      expect(selected.value.messages).toEqual([]);
      wrapper.unmount();
    }
  );

  it('removes stale permissions when authenticated detail omits transport options', async () => {
    const state = {
      allConversations: [
        { id: 8, account_id: 1, whatsapp_transport_options: options },
      ],
    };
    const commit = (type, payload) => mutations[type](state, payload);
    ConversationApi.show.mockResolvedValue({ data: { id: 8, account_id: 1 } });
    await actions.refreshWhatsappTransport({ commit }, 8);
    expect(state.allConversations[0].whatsapp_transport_options).toBeNull();
  });

  it('does not overwrite another account after a delayed response', () => {
    const state = { allConversations: [{ id: 8, account_id: 2 }] };
    mutations.hydrateWhatsappTransport(state, {
      conversationId: 8,
      accountId: 1,
      options,
    });
    expect(state.allConversations[0]).not.toHaveProperty(
      'whatsapp_transport_options'
    );
  });

  it('does not create an orphan conversation for a delayed response', () => {
    const state = { allConversations: [] };
    mutations.hydrateWhatsappTransport(state, {
      conversationId: 8,
      accountId: 1,
      options,
    });
    expect(state.allConversations).toEqual([]);
  });

  it('hydrates a previous conversation without switching the current selection', () => {
    const state = {
      allConversations: [
        { id: 8, account_id: 1 },
        { id: 9, account_id: 1 },
      ],
      selectedChatId: 9,
    };
    mutations.hydrateWhatsappTransport(state, {
      conversationId: 8,
      accountId: 1,
      options,
    });
    expect(state.selectedChatId).toBe(9);
    expect(state.allConversations[0].whatsapp_transport_options).toEqual(
      options
    );
    expect(state.allConversations[1]).not.toHaveProperty(
      'whatsapp_transport_options'
    );
  });

  it('leaves existing metadata untouched on a network failure', async () => {
    const commit = vi.fn();
    ConversationApi.show.mockRejectedValue(new Error('offline'));
    await actions.refreshWhatsappTransport({ commit }, 8);
    expect(commit).not.toHaveBeenCalled();
  });

  it.each([
    { meta: { channel: 'Channel::Email' } },
    { meta: { channel: 'Channel::Whatsapp' }, group: true },
  ])('does not fetch individual transport options for %j', async details => {
    const commit = vi.fn();
    const dispatch = vi.fn();
    await actions.setActiveChat(
      { commit, dispatch },
      { data: { id: 8, dataFetched: true, ...details } }
    );
    expect(dispatch).not.toHaveBeenCalled();
    expect(commit).toHaveBeenCalledWith(
      types.SET_CURRENT_CHAT_WINDOW,
      expect.objectContaining({ id: 8 })
    );
  });
});
