import { computed, reactive, toValue } from 'vue';
import api from 'dashboard/api/webAttendance';

const states = reactive({});
const revisions = {};

export function useWebAttendance(accountId, conversationId) {
  const key = computed(
    () => `${toValue(accountId)}:${toValue(conversationId)}`
  );
  const attendance = computed(() => states[key.value] || null);

  const refresh = async () => {
    const requestKey = key.value;
    const revision = (revisions[requestKey] || 0) + 1;
    revisions[requestKey] = revision;
    const { data } = await api.show(toValue(conversationId));
    if (revisions[requestKey] === revision) states[requestKey] = data;
    return states[requestKey];
  };

  const seen = async destination => {
    const requestKey = key.value;
    const revision = (revisions[requestKey] || 0) + 1;
    revisions[requestKey] = revision;
    const { data } = await api.seen(toValue(conversationId), destination);
    if (revisions[requestKey] === revision) states[requestKey] = data;
  };

  return { attendance, refresh, seen };
}
