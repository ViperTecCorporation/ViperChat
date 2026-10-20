import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useStoreGetters } from 'dashboard/composables/store';

export function useLabelCreation() {
  const { currentAccount } = useAccount();
  const getters = useStoreGetters();
  const canCreateLabels = computed(() => {
    const role = getters.getCurrentRole.value;
    return (
      role === 'administrator' ||
      (role === 'agent' &&
        currentAccount.value?.settings?.allow_agents_to_create_labels === true)
    );
  });
  return { canCreateLabels };
}
