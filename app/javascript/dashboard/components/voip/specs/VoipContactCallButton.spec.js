import { mount } from '@vue/test-utils';
import VoipContactCallButton from '../VoipContactCallButton.vue';

const phone = vi.hoisted(() => ({ openDialer: vi.fn(), dial: vi.fn() }));
vi.mock('dashboard/stores/agentVoip', () => ({
  useAgentVoipStore: () => phone,
}));

describe('VoipContactCallButton', () => {
  beforeEach(() => vi.clearAllMocks());

  it('opens the global dialer with a normalized telephone, without calling or navigating', async () => {
    const parentClick = vi.fn();
    const wrapper = mount({
      components: { VoipContactCallButton },
      template:
        '<div @click="parentClick"><VoipContactCallButton :contact="contact" /></div>',
      setup: () => ({
        parentClick,
        contact: {
          id: 231,
          name: 'Contact',
          phone_number: '+55 (66) 99626-9251',
        },
      }),
    });
    const button = wrapper.get('button');
    expect(button.attributes('aria-label')).toBeTruthy();
    expect(button.find('.i-lucide-phone').exists()).toBe(true);
    await button.trigger('click');
    expect(phone.openDialer).toHaveBeenCalledExactlyOnceWith({
      address: '+5566996269251',
      serviceId: null,
      kind: 'manual',
    });
    expect(phone.dial).not.toHaveBeenCalled();
    expect(parentClick).not.toHaveBeenCalled();
  });

  it('supports the contact card camelCase representation and updated telephone', async () => {
    const wrapper = mount(VoipContactCallButton, {
      props: { contact: { phoneNumber: '+5566996269251' } },
    });
    await wrapper.setProps({ contact: { phoneNumber: '+5565996598456' } });
    await wrapper.get('button').trigger('click');
    expect(phone.openDialer).toHaveBeenCalledExactlyOnceWith({
      address: '+5565996598456',
      serviceId: null,
      kind: 'manual',
    });
  });

  it.each([
    {},
    { phone_number: '242309471989955@lid' },
    { phone_number: 'BR.2339818310092335' },
    { phone_number: '120363123456789@g.us' },
    { phone_number: '123456789012345678' },
    { phone_number: '+5566996269251', group: true },
    { phone_number: '+5566996269251', is_group: true },
    { phone_number: '+5566996269251', email: '120363123456789@g.us' },
    { phone_number: '+5566996269251', identifier: '120363123456789@g.us' },
    { phoneNumber: '+5566996269251', additionalAttributes: { is_group: true } },
    { phone_number: '+5566996269251', additional_attributes: { group: true } },
  ])(
    'does not offer dialing for missing phone or provider/group identifiers: %j',
    contact => {
      const wrapper = mount(VoipContactCallButton, { props: { contact } });
      expect(wrapper.find('button').exists()).toBe(false);
      expect(phone.openDialer).not.toHaveBeenCalled();
      expect(phone.dial).not.toHaveBeenCalled();
    }
  );
});
