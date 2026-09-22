export const DEFAULT_NAVIGATION_SHORTCUTS = Object.freeze({
  all: 'Alt+T',
  me: 'Alt+M',
  mentions: 'Alt+@',
  groups: 'Alt+G',
  unattended: 'Alt+N',
  participating: 'Alt+P',
  internal: 'Alt+I',
});

export const navigationShortcuts = settings => ({
  ...DEFAULT_NAVIGATION_SHORTCUTS,
  ...settings?.navigation_shortcuts,
});

// Store printable keys rather than physical positions so labels match the keyboard.
// Shift is implicit in @ (Alt+Shift+2 on common layouts).
export function shortcutFromEvent(event) {
  if (event.isComposing || event.getModifierState?.('AltGraph')) return '';
  const key = event.key?.toUpperCase();
  if (!key || key.length !== 1 || key === ' ') return '';
  if (!event.altKey && !event.ctrlKey && !event.metaKey) return '';
  return [
    event.ctrlKey && 'Ctrl',
    event.altKey && 'Alt',
    event.metaKey && 'Meta',
    event.shiftKey && key !== '@' && 'Shift',
    key,
  ]
    .filter(Boolean)
    .join('+');
}
