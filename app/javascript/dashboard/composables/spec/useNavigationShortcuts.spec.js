import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import { useNavigationShortcuts } from '../useNavigationShortcuts';

const mocks = vi.hoisted(() => ({
  push: vi.fn(),
  permissions: ['agent'],
  hidden: false,
  settings: null,
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
  useRouter: () => ({
    push: mocks.push,
    resolve: () => ({ meta: { permissions: ['agent', 'administrator'] } }),
  }),
}));
vi.mock('vuex', () => ({
  useStore: () => ({
    getters: {
      getCurrentUser: {},
      'accounts/isFeatureEnabledonAccount': () => mocks.hidden,
    },
  }),
}));
vi.mock('../../helper/permissionsHelper', () => ({
  getUserPermissions: () => mocks.permissions,
}));
vi.mock('../useUISettings', () => ({
  useUISettings: () => ({ uiSettings: mocks.settings }),
}));

describe('navigation shortcut listener', () => {
  let wrapper;
  beforeEach(() => {
    mocks.push.mockClear();
    mocks.permissions = ['agent'];
    mocks.hidden = false;
    mocks.settings = ref({});
    wrapper = mount(
      {
        setup() {
          useNavigationShortcuts();
        },
        template: '<div><input /></div>',
      },
      { attachTo: document.body }
    );
  });
  afterEach(() => wrapper.unmount());
  it.each([
    ['t', 'home', 'all'],
    ['m', 'home', 'me'],
    ['g', 'home', 'groups'],
    ['i', 'home', 'internal'],
    ['@', 'conversation_mentions'],
    ['n', 'conversation_unattended'],
    ['p', 'conversation_participating'],
  ])('routes Alt+%s to the correct destination', (key, name, tab) => {
    document.dispatchEvent(
      new KeyboardEvent('keydown', { key, altKey: true, shiftKey: key === '@' })
    );
    expect(mocks.push).toHaveBeenCalledWith({
      name,
      params: { accountId: 1 },
      query: tab ? { navigation_tab: tab } : {},
    });
  });
  it('uses updated preferences without remounting', () => {
    mocks.settings.value = { navigation_shortcuts: { me: 'Ctrl+Q' } };
    document.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'm', altKey: true })
    );
    expect(mocks.push).not.toHaveBeenCalled();
    document.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'q', ctrlKey: true })
    );
    expect(mocks.push).toHaveBeenCalledOnce();
  });
  it('does not intercept typing', () => {
    wrapper
      .find('input')
      .element.dispatchEvent(
        new KeyboardEvent('keydown', { key: 'm', altKey: true, bubbles: true })
      );
    expect(mocks.push).not.toHaveBeenCalled();
  });
  it('respects hidden all and custom role permissions', () => {
    mocks.hidden = true;
    document.dispatchEvent(
      new KeyboardEvent('keydown', { key: 't', altKey: true })
    );
    mocks.permissions = ['contact_manage'];
    document.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'g', altKey: true })
    );
    expect(mocks.push).not.toHaveBeenCalled();
  });
  it('stops conflicting legacy handlers', () => {
    const legacy = vi.fn();
    document.addEventListener('keydown', legacy);
    document.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'm', altKey: true })
    );
    document.removeEventListener('keydown', legacy);
    expect(legacy).not.toHaveBeenCalled();
  });
});
