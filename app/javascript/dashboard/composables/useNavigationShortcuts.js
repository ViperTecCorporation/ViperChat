import { onMounted, onUnmounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useUISettings } from './useUISettings';
import {
  navigationShortcuts,
  shortcutFromEvent,
} from '../helper/navigationShortcuts';
import { getUserPermissions } from '../helper/permissionsHelper';
import { ASSIGNEE_TYPE_TAB_PERMISSIONS } from '../constants/permissions';

const DEFAULT_ACTIONS = {
  all: 'home',
  me: 'home',
  groups: 'home',
  internal: 'home',
  mentions: 'conversation_mentions',
  unattended: 'conversation_unattended',
  participating: 'conversation_participating',
};

export function useNavigationShortcuts() {
  const { uiSettings } = useUISettings();
  const route = useRoute();
  const router = useRouter();
  const store = useStore();
  const onKeydown = event => {
    if (
      event.repeat ||
      event.defaultPrevented ||
      event.target?.closest?.(
        'input, textarea, select, [contenteditable="true"], [role="dialog"], ninja-keys'
      )
    )
      return;
    const shortcut = shortcutFromEvent(event);
    if (!shortcut) return;
    const action = Object.keys(DEFAULT_ACTIONS).find(
      key => navigationShortcuts(uiSettings.value)[key] === shortcut
    );
    if (!action || !route.params.accountId) return;
    const accountId = Number(route.params.accountId);
    const permissions = getUserPermissions(
      store.getters.getCurrentUser,
      accountId
    );
    const tab = ASSIGNEE_TYPE_TAB_PERMISSIONS[action];
    const destination = DEFAULT_ACTIONS[action];
    const required =
      tab?.permissions ||
      router.resolve({ name: destination, params: { accountId } }).meta
        .permissions;
    if (!required?.some(permission => permissions.includes(permission))) return;
    if (
      action === 'all' &&
      !permissions.includes('administrator') &&
      store.getters['accounts/isFeatureEnabledonAccount'](
        accountId,
        'hide_all_chats_for_agent'
      )
    )
      return;
    event.preventDefault();
    event.stopImmediatePropagation();
    router.push({
      name: destination,
      params: { accountId },
      query: tab ? { navigation_tab: action } : {},
    });
  };
  onMounted(() => document.addEventListener('keydown', onKeydown, true));
  onUnmounted(() => document.removeEventListener('keydown', onKeydown, true));
}
