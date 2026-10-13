import { mount } from '@vue/test-utils';
import SidebarAccountSwitcher from '../SidebarAccountSwitcher.vue';

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: { value: 1 },
    currentAccount: { value: { id: 1, name: 'Empresa principal' } },
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter => {
    const values = {
      getCurrentUser: {
        accounts: [
          { id: 1, name: 'Empresa principal', role: 'agent' },
          { id: 2, name: 'Empresa secundária', role: 'agent' },
        ],
      },
      getUserAccounts: [
        { id: 1, name: 'Empresa principal' },
        { id: 2, name: 'Empresa secundária' },
      ],
      'globalConfig/get': { createNewAccountFromDashboard: false },
    };
    return { value: values[getter] };
  },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const DropdownContainerStub = {
  methods: { toggle() {} },
  template: `
    <div>
      <slot name="trigger" :toggle="toggle" :is-open="true" />
      <slot />
    </div>
  `,
};

const DropdownBodyStub = {
  name: 'DropdownBody',
  template: '<div><slot /></div>',
};

describe('SidebarAccountSwitcher', () => {
  afterEach(() => vi.unstubAllGlobals());

  it.each([false, true])(
    'switches account with a fresh page (native: %s)',
    async native => {
      const location = { href: '/', reload: vi.fn() };
      const history = { replaceState: vi.fn() };
      vi.stubGlobal('window', {
        MouseEvent: window.MouseEvent,
        Event: window.Event,
        chatwootConfig: { isNativeApp: native },
        location,
        history,
      });
      const wrapper = mount(SidebarAccountSwitcher, {
        global: {
          stubs: {
            DropdownContainer: DropdownContainerStub,
            DropdownBody: DropdownBodyStub,
            DropdownSection: { template: '<div><slot /></div>' },
            DropdownItem: {
              template: '<button><slot name="label" /></button>',
            },
            Logo: true,
            Icon: true,
            ButtonNext: true,
          },
        },
      });
      await wrapper.get('#account-2').trigger('click');
      if (native) {
        expect(history.replaceState).toHaveBeenCalledWith(
          null,
          '',
          '/#/app/accounts/2/dashboard'
        );
        expect(location.reload).toHaveBeenCalledOnce();
        expect(location.href).toBe('/');
      } else {
        expect(location.href).toBe('/app/accounts/2/dashboard');
        expect(history.replaceState).not.toHaveBeenCalled();
        expect(location.reload).not.toHaveBeenCalled();
      }
    }
  );
  it('makes the logo part of the expanded account switch trigger', () => {
    const wrapper = mount(SidebarAccountSwitcher, {
      global: {
        stubs: {
          DropdownContainer: DropdownContainerStub,
          DropdownBody: DropdownBodyStub,
          DropdownSection: { template: '<div><slot /></div>' },
          DropdownItem: { template: '<div><slot name="label" /></div>' },
          Logo: { template: '<span data-test-id="account-logo" />' },
          Icon: true,
          ButtonNext: true,
        },
      },
    });

    const trigger = wrapper.get('#sidebar-account-switcher');
    expect(trigger.find('[data-test-id="account-logo"]').exists()).toBe(true);
    expect(trigger.attributes('aria-expanded')).toBe('true');
  });

  it('limits the account menu width to the mobile viewport', () => {
    const wrapper = mount(SidebarAccountSwitcher, {
      global: {
        stubs: {
          DropdownContainer: DropdownContainerStub,
          DropdownBody: DropdownBodyStub,
          DropdownSection: { template: '<div><slot /></div>' },
          DropdownItem: { template: '<div><slot name="label" /></div>' },
          Logo: true,
          Icon: true,
          ButtonNext: true,
        },
      },
    });

    const menu = wrapper.findComponent({ name: 'DropdownBody' });
    expect(menu.classes()).toEqual(
      expect.arrayContaining(['w-[calc(100vw-1rem)]', 'max-w-80'])
    );
  });
});
