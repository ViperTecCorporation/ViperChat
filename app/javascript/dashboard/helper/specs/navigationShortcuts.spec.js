import {
  DEFAULT_NAVIGATION_SHORTCUTS,
  navigationShortcuts,
  shortcutFromEvent,
} from '../navigationShortcuts';

describe('navigation shortcuts', () => {
  it('uses all seven defaults and merges user overrides', () => {
    expect(Object.keys(DEFAULT_NAVIGATION_SHORTCUTS)).toHaveLength(7);
    expect(
      navigationShortcuts({ navigation_shortcuts: { me: 'Ctrl+M' } })
    ).toEqual({ ...DEFAULT_NAVIGATION_SHORTCUTS, me: 'Ctrl+M' });
  });
  it.each(['t', 'T'])('normalizes Alt plus %s', key => {
    expect(shortcutFromEvent({ key, altKey: true })).toBe('Alt+T');
  });
  it('supports the Shift required to type @', () => {
    expect(shortcutFromEvent({ key: '@', altKey: true, shiftKey: true })).toBe(
      'Alt+@'
    );
  });
  it('preserves explicit modifier combinations', () => {
    expect(shortcutFromEvent({ key: 'g', ctrlKey: true, shiftKey: true })).toBe(
      'Ctrl+Shift+G'
    );
  });
  it.each([
    { key: 't' },
    { key: 'Alt', altKey: true },
    { key: 't', altKey: true, isComposing: true },
    { key: '@', ctrlKey: true, altKey: true, getModifierState: () => true },
  ])('ignores typing, modifiers, IME and AltGraph: %o', event => {
    expect(shortcutFromEvent(event)).toBe('');
  });
});
