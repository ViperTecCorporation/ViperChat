import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import UnoapiClientProfile from '../UnoapiClientProfile.vue';
import UnoapiConfiguration from '../UnoapiConfiguration.vue';
import UnoapiSettingLabel from '../UnoapiSettingLabel.vue';
import locale from 'dashboard/i18n/locale/pt_BR/inboxMgmt.json';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

describe('UnoapiClientProfile', () => {
  it('offers default and both Android profiles with explanatory help', async () => {
    const labels = locale.INBOX_MGMT.ADD.WHATSAPP.CLIENT_PROFILE;
    const wrapper = mount(UnoapiClientProfile, {
      props: { modelValue: '' },
      global: { mocks: { $t: key => labels[key.split('.').at(-1)] } },
    });

    expect(
      wrapper.findAll('option').map(option => option.element.value)
    ).toEqual(['', 'wa_personal', 'wa_business']);
    expect(wrapper.find('select').element.value).toBe('');
    expect(wrapper.findComponent(UnoapiSettingLabel).props('help')).toContain(
      'WA Business para WhatsApp Business'
    );
    await wrapper.find('select').setValue('wa_business');
    expect(wrapper.emitted('update:modelValue')).toEqual([['wa_business']]);
    await wrapper.setProps({ modelValue: 'wa_personal' });
    expect(wrapper.find('select').element.value).toBe('wa_personal');
  });

  it.each([
    ['qrcode', 'wa_personal', 'wa_personal'],
    ['qrcode', 'wa_business', 'wa_business'],
    ['qrcode', '', null],
    ['pairing_code', 'wa_business', null],
  ])(
    'saves the profile for %s / %s',
    async (connectionType, profile, expected) => {
      const dispatch = vi.fn().mockResolvedValue({});
      const context = {
        ...UnoapiConfiguration.data(),
        inbox: {
          id: 1,
          provider_config: { zapo_web_client_profile: 'wa_personal' },
        },
        globalConfig: {},
        connectionType,
        zapoWebClientProfile: profile,
        $store: { dispatch },
        $t: key => key,
      };
      await UnoapiConfiguration.methods.updateInbox.call(context);

      expect(dispatch).toHaveBeenCalledWith(
        'inboxes/updateInbox',
        expect.objectContaining({
          channel: expect.objectContaining({
            provider_config: expect.objectContaining({
              connection_type: connectionType,
              zapo_web_client_profile: expected,
            }),
          }),
        })
      );
    }
  );

  it('restores the saved profile when loading the inbox', () => {
    const context = {
      ...UnoapiConfiguration.data(),
      inbox: { provider_config: { zapo_web_client_profile: 'wa_business' } },
      globalConfig: {},
    };
    UnoapiConfiguration.methods.setDefaults.call(context);
    expect(context.zapoWebClientProfile).toBe('wa_business');
    context.inbox.provider_config = {};
    UnoapiConfiguration.methods.setDefaults.call(context);
    expect(context.zapoWebClientProfile).toBe('');
  });
});
