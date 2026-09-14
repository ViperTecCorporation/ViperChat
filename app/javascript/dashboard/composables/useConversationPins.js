import { computed } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { pinnedConversationIds } from 'dashboard/helper/conversationPins';
import ConversationApi from 'dashboard/api/conversations';
import types from 'dashboard/store/mutation-types';

export function useConversationPins() {
  const store = useStore();
  const settings = useMapGetter('getUISettings');
  const accountId = useMapGetter('getCurrentAccountId');
  const pins = computed(() =>
    pinnedConversationIds(settings.value, accountId.value)
  );
  const isPinned = id => pins.value.includes(Number(id));
  const setPinned = async (id, pinned) => {
    const targetAccount = accountId.value;
    const { data } = await ConversationApi.setPinned(id, pinned);
    store.commit(types.SET_CURRENT_USER_UI_SETTINGS, {
      uiSettings: {
        pinned_conversations: {
          ...settings.value?.pinned_conversations,
          [targetAccount]: data.pinned_conversations,
        },
      },
    });
  };
  return { pins, isPinned, setPinned };
}
