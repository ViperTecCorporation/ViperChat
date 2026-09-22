import { computed } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { archivedConversationIds } from 'dashboard/helper/conversationArchives';
import api from 'dashboard/api/conversations';
import types from 'dashboard/store/mutation-types';
import { emitter } from 'shared/helpers/mitt';

export function useConversationArchives() {
  const store = useStore();
  const settings = useMapGetter('getUISettings');
  const accountId = useMapGetter('getCurrentAccountId');
  const archives = computed(() =>
    archivedConversationIds(settings.value, accountId.value)
  );
  const setArchived = async (id, archived) => {
    const targetAccount = accountId.value;
    const { data } = await api.setArchived(id, archived);
    store.commit(types.SET_CURRENT_USER_UI_SETTINGS, {
      uiSettings: {
        archived_conversations: {
          ...settings.value?.archived_conversations,
          [targetAccount]: data.archived_conversations,
        },
      },
    });
    emitter.emit('refresh_conversation_list');
  };
  return { archives, setArchived };
}
