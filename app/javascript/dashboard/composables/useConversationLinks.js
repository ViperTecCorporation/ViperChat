import { ref, watch } from 'vue';
import api from 'dashboard/api/conversations';

export function useConversationLinks(props) {
  const links = ref([]);
  const total = ref(0);
  const hasMore = ref(false);
  const loading = ref(false);
  const error = ref(false);
  let page = 1;
  let generation = 0;
  const load = async (append = false) => {
    if (!props.show || !props.conversationId) return;
    generation += 1;
    const request = generation;
    loading.value = true;
    error.value = false;
    try {
      const nextPage = append ? page + 1 : 1;
      const { data } = await api.getLinks(props.conversationId, nextPage);
      if (request !== generation) return;
      links.value = append ? [...links.value, ...data.payload] : data.payload;
      total.value = data.total_count;
      hasMore.value = data.has_more;
      page = nextPage;
    } catch {
      if (request === generation) error.value = true;
    } finally {
      if (request === generation) loading.value = false;
    }
  };
  watch(
    () => [props.show, props.conversationId],
    () => {
      generation += 1;
      links.value = [];
      total.value = 0;
      hasMore.value = false;
      loading.value = false;
      error.value = false;
      load();
    },
    { immediate: true }
  );
  return { links, total, hasMore, loading, error, load };
}
