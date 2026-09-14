import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useRoute, useRouter } from 'vue-router';
import { useNavigationShortcuts } from 'dashboard/composables/useNavigationShortcuts';

export function useSidebarKeyboardShortcuts(toggleShortcutModalFn) {
  useNavigationShortcuts();
  const route = useRoute();
  const router = useRouter();

  const isCurrentRouteSameAsNavigation = routeName => {
    return route.name === routeName;
  };

  const navigateToRoute = routeName => {
    if (!isCurrentRouteSameAsNavigation(routeName)) {
      router.push({ name: routeName });
    }
  };
  const keyboardEvents = {
    '$mod+Slash': {
      action: () => toggleShortcutModalFn(true),
    },
    '$mod+Escape': {
      action: () => toggleShortcutModalFn(false),
    },
    'Alt+KeyC': {
      action: () => navigateToRoute('home'),
    },
    'Alt+KeyV': {
      action: () => navigateToRoute('contacts_dashboard'),
    },
    'Alt+KeyR': {
      action: () => navigateToRoute('account_overview_reports'),
    },
    'Alt+KeyS': {
      action: () => navigateToRoute('agent_list'),
    },
  };

  return useKeyboardEvents(keyboardEvents);
}
