import { setupMobileNavigation } from '../mobileNavigation';

describe('superadmin mobile navigation', () => {
  let breakpointChange;
  beforeEach(() => {
    document.body.innerHTML =
      '<button id="super-admin-menu-toggle" aria-expanded="false"></button><nav id="super-admin-navigation" class="hidden md:flex"><a href="#test">Account</a></nav>';
    vi.stubGlobal('matchMedia', () => ({
      addEventListener: (_, callback) => {
        breakpointChange = callback;
      },
    }));
    setupMobileNavigation();
  });
  afterEach(() => vi.unstubAllGlobals());

  it('toggles the navigation and its accessible expanded state', () => {
    const button = document.querySelector('button');
    button.click();
    expect(button.getAttribute('aria-expanded')).toBe('true');
    expect(document.querySelector('nav').classList.contains('hidden')).toBe(
      false
    );
    button.click();
    expect(button.getAttribute('aria-expanded')).toBe('false');
  });
  it('closes on Escape and restores focus', () => {
    const button = document.querySelector('button');
    button.click();
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    expect(button.getAttribute('aria-expanded')).toBe('false');
    expect(document.activeElement).toBe(button);
  });
  it('closes after navigation', () => {
    document.querySelector('button').click();
    document.querySelector('a').click();
    expect(document.querySelector('nav').classList.contains('hidden')).toBe(
      true
    );
  });
  it('resets the mobile state when the breakpoint changes', () => {
    document.querySelector('button').click();
    breakpointChange();
    expect(document.querySelector('button').getAttribute('aria-expanded')).toBe(
      'false'
    );
  });

  it('keeps wide tables in their own scroll container without duplicating wrappers', () => {
    document.body.insertAdjacentHTML(
      'beforeend',
      '<main><table><tr><td>Value</td></tr></table></main>'
    );
    setupMobileNavigation();
    setupMobileNavigation();
    expect(document.querySelectorAll('[data-scroll-table]')).toHaveLength(1);
    expect(
      document
        .querySelector('table')
        .parentElement.classList.contains('overflow-x-auto')
    ).toBe(true);
  });
});
