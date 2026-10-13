import { shallowMount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import ContactForm from './ContactForm.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

describe('ContactForm avatar deletion', () => {
  it.each(['+5566996890270', ''])(
    'keeps the phone unchanged and allows saving after removing the avatar (%s)',
    async phoneNumber => {
      const dispatch = vi.fn().mockResolvedValue({});
      const onSubmit = vi.fn().mockResolvedValue({});
      const wrapper = shallowMount(ContactForm, {
        props: {
          contact: {
            id: 42,
            name: 'Contato de teste',
            phone_number: phoneNumber,
            thumbnail: 'https://example.com/avatar.png',
          },
          onSubmit,
        },
        global: {
          stubs: { 'woot-phone-input': true, 'woot-input': true },
          mocks: { $t: key => key, $store: { dispatch } },
        },
      });
      const originalDialCode = wrapper.vm.activeDialCode;
      expect(wrapper.vm.isPhoneNumberNotValid).toBe(false);

      await wrapper.vm.handleAvatarDelete();
      expect(dispatch).toHaveBeenCalledWith('contacts/deleteAvatar', 42);
      expect(wrapper.vm.avatarUrl).toBe('');
      expect(wrapper.vm.activeDialCode).toBe(originalDialCode);
      expect(wrapper.vm.phoneNumber).toBe(phoneNumber);
      expect(wrapper.vm.isPhoneNumberNotValid).toBe(false);

      await wrapper.vm.handleSubmit();
      expect(onSubmit).toHaveBeenCalledWith(
        expect.objectContaining({ id: 42, phone_number: phoneNumber })
      );
      expect(wrapper.emitted('success')).toHaveLength(1);
    }
  );

  it('preserves the avatar and phone when deletion fails', async () => {
    const wrapper = shallowMount(ContactForm, {
      props: {
        contact: {
          id: 42,
          name: 'Contato de teste',
          phone_number: '+5566996890270',
          thumbnail: 'https://example.com/avatar.png',
        },
      },
      global: {
        stubs: { 'woot-phone-input': true, 'woot-input': true },
        mocks: {
          $t: key => key,
          $store: { dispatch: vi.fn().mockRejectedValue(new Error('Failed')) },
        },
      },
    });
    await wrapper.vm.handleAvatarDelete();
    expect(wrapper.vm.avatarUrl).toBe('https://example.com/avatar.png');
    expect(wrapper.vm.activeDialCode).toBe('+55');
    expect(wrapper.vm.isPhoneNumberNotValid).toBe(false);
  });
});
