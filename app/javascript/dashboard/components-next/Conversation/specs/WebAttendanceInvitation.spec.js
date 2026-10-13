import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import Invitation from '../WebAttendanceInvitation.vue';
import api from 'dashboard/api/webAttendance';

const mocks = vi.hoisted(() => ({
  refresh: vi.fn(),
  alert: vi.fn(),
  state: null,
  invitationMessage: '',
}));

vi.mock('dashboard/api/webAttendance', () => ({
  default: { create: vi.fn(), fallback: vi.fn(), revoke: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: mocks.alert }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key => {
    if (key === 'getSelectedChat') return ref({ id: 42, inbox_id: 7 });
    if (key === 'getCurrentAccountId') return ref(1);
    return ref(() => ({
      web_attendance_button_text: 'Continuar atendimento',
      web_attendance_invitation_message: mocks.invitationMessage,
    }));
  },
}));
vi.mock('dashboard/composables/useWebAttendance', () => ({
  useWebAttendance: () => ({ attendance: mocks.state, refresh: mocks.refresh }),
}));

const ButtonStub = {
  props: ['label', 'disabled'],
  emits: ['click'],
  template:
    '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
};
const open = async () => {
  const wrapper = mount(Invitation, {
    props: { show: false },
    global: {
      stubs: { Modal: { template: '<div><slot /></div>' }, Button: ButtonStub },
    },
  });
  await wrapper.setProps({ show: true });
  await flushPromises();
  return wrapper;
};
const button = (wrapper, key) =>
  wrapper.findAll('button').find(b => b.text() === `WEB_ATTENDANCE.${key}`);

beforeEach(() => {
  vi.clearAllMocks();
  mocks.invitationMessage = '';
  mocks.state = ref({
    enabled: true,
    can_invite: true,
    provider: 'unoapi',
    invitation_max_length: 4096,
    button_max_length: 60,
    active: false,
    invitations: [],
    button_text: 'Continuar atendimento',
  });
  mocks.refresh.mockResolvedValue();
  api.create.mockResolvedValue({ data: { message: { id: 1 } } });
  api.fallback.mockResolvedValue();
  api.revoke.mockResolvedValue();
});

describe('web invitation confirmation', () => {
  it('starts with the inbox default and keeps edits local to the invitation', async () => {
    mocks.invitationMessage = ' Atendimento personalizado ';
    const wrapper = await open();
    expect(wrapper.get('textarea').element.value).toBe(
      'Atendimento personalizado'
    );
    await wrapper.get('textarea').setValue('Convite editado');
    expect(mocks.invitationMessage).toBe(' Atendimento personalizado ');
    wrapper.unmount();
  });

  it('uses the built-in default when the inbox message is blank', async () => {
    mocks.invitationMessage = '   ';
    const wrapper = await open();
    expect(wrapper.get('textarea').element.value).toBe(
      'WEB_ATTENDANCE.DEFAULT_CONTENT'
    );
    wrapper.unmount();
  });
  it('previews the configured CTA and requires an explicit send', async () => {
    const wrapper = await open();
    expect(wrapper.text()).toContain('Continuar atendimento');
    expect(api.create).not.toHaveBeenCalled();
    await wrapper.find('textarea').setValue('Continue aqui');
    await button(wrapper, 'SEND').trigger('click');
    await flushPromises();
    expect(api.create).toHaveBeenCalledWith(42, {
      content: 'Continue aqui',
      request_id: expect.stringMatching(
        /^[\da-f]{8}-[\da-f]{4}-4[\da-f]{3}-[89ab][\da-f]{3}-[\da-f]{12}$/i
      ),
    });
    wrapper.unmount();
  });

  it('reuses the request ID after a failed HTTP request', async () => {
    api.create.mockRejectedValue(new Error('network'));
    const wrapper = await open();
    await button(wrapper, 'SEND').trigger('click');
    await flushPromises();
    await button(wrapper, 'SEND').trigger('click');
    await flushPromises();
    expect(api.create.mock.calls[0][1].request_id).toBe(
      api.create.mock.calls[1][1].request_id
    );
    wrapper.unmount();
  });

  it('offers fallback only after CTA failure and sends it manually', async () => {
    mocks.state.value.invitations = [
      { id: 5, failed: true, error: 'CTA rejected', status: 'failed' },
    ];
    const wrapper = await open();
    expect(wrapper.text()).toContain('CTA rejected');
    expect(api.fallback).not.toHaveBeenCalled();
    await button(wrapper, 'FALLBACK').trigger('click');
    await flushPromises();
    expect(api.fallback).toHaveBeenCalledWith(42, 5);
    wrapper.unmount();
  });

  it('blocks a second invitation while processing', async () => {
    mocks.state.value.invitations = [
      { id: 5, status: 'progress', active: false, failed: false },
    ];
    const wrapper = await open();
    expect(button(wrapper, 'SEND').attributes('disabled')).toBeDefined();
    expect(button(wrapper, 'FALLBACK')).toBeUndefined();
    wrapper.unmount();
  });

  it('revokes active access on explicit action', async () => {
    mocks.state.value.active = true;
    const wrapper = await open();
    await button(wrapper, 'REVOKE').trigger('click');
    await flushPromises();
    expect(api.revoke).toHaveBeenCalledWith(42);
    wrapper.unmount();
  });

  it('blocks invitation and text fallback outside the window but keeps active access and edited content', async () => {
    mocks.state.value = {
      ...mocks.state.value,
      provider: 'whatsapp_cloud',
      can_invite: false,
      active: true,
      invitation_max_length: 1024,
      button_max_length: 20,
      button_text: 'Abrir atendimento',
      invitations: [{ id: 5, failed: true, status: 'failed' }],
    };
    const wrapper = await open();
    await wrapper.get('textarea').setValue('Draft invitation');
    expect(wrapper.text()).toContain('WEB_ATTENDANCE.INVITE_UNAVAILABLE');
    expect(button(wrapper, 'SEND').attributes('disabled')).toBeDefined();
    expect(button(wrapper, 'FALLBACK').attributes('disabled')).toBeDefined();
    await wrapper.vm.send();
    await wrapper.vm.fallback();
    expect(api.create).not.toHaveBeenCalled();
    expect(api.fallback).not.toHaveBeenCalled();
    expect(button(wrapper, 'REVOKE').attributes('disabled')).toBeUndefined();
    mocks.state.value.can_invite = true;
    await flushPromises();
    expect(wrapper.get('textarea').element.value).toBe('Draft invitation');
    expect(button(wrapper, 'SEND').attributes('disabled')).toBeUndefined();
    await button(wrapper, 'FALLBACK').trigger('click');
    expect(api.fallback).toHaveBeenCalledWith(42, 5);
    wrapper.unmount();
  });

  it.each([
    ['whatsapp_cloud', 1024, 20],
    ['unoapi', 4096, 60],
  ])(
    'enforces %s presenter body and button limits',
    async (provider, maxLength, buttonMax) => {
      Object.assign(mocks.state.value, {
        provider,
        invitation_max_length: maxLength,
        button_max_length: buttonMax,
        button_text: 'x'.repeat(buttonMax),
      });
      const wrapper = await open();
      expect(wrapper.get('textarea').attributes('maxlength')).toBe(
        String(maxLength)
      );
      await wrapper.get('textarea').setValue('x'.repeat(maxLength + 1));
      await wrapper.vm.send();
      expect(api.create).not.toHaveBeenCalled();
      expect(wrapper.text()).toContain('WEB_ATTENDANCE.LIMIT_ERROR');
      await wrapper.get('textarea').setValue('x'.repeat(maxLength));
      mocks.state.value.button_text = 'x'.repeat(buttonMax + 1);
      await flushPromises();
      expect(button(wrapper, 'SEND').attributes('disabled')).toBeDefined();
      mocks.state.value.button_text = 'x'.repeat(buttonMax);
      await flushPromises();
      await button(wrapper, 'SEND').trigger('click');
      expect(api.create).toHaveBeenCalledWith(
        42,
        expect.objectContaining({ content: 'x'.repeat(maxLength) })
      );
      wrapper.unmount();
    }
  );

  it('does not assume can_invite when the API state is missing it', async () => {
    delete mocks.state.value.can_invite;
    const wrapper = await open();
    expect(button(wrapper, 'SEND').attributes('disabled')).toBeDefined();
    await wrapper.vm.send();
    expect(api.create).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('uses Cloud fallback limits when the presenter omits optional limits', async () => {
    mocks.state.value.provider = 'whatsapp_cloud';
    mocks.state.value.button_text = 'Abrir atendimento';
    delete mocks.state.value.invitation_max_length;
    delete mocks.state.value.button_max_length;
    const wrapper = await open();
    expect(wrapper.get('textarea').attributes('maxlength')).toBe('1024');
    await wrapper.get('textarea').setValue('Allowed Cloud invitation');
    await button(wrapper, 'SEND').trigger('click');
    expect(api.create).toHaveBeenCalledWith(
      42,
      expect.objectContaining({ content: 'Allowed Cloud invitation' })
    );
    wrapper.unmount();
  });

  it('blocks send and fallback while fetching fresh eligibility or after a load error', async () => {
    let complete;
    mocks.refresh.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          complete = resolve;
        })
    );
    mocks.state.value.invitations = [{ id: 5, failed: true, status: 'failed' }];
    const wrapper = await open();
    expect(button(wrapper, 'SEND').attributes('disabled')).toBeDefined();
    expect(button(wrapper, 'FALLBACK').attributes('disabled')).toBeDefined();
    await wrapper.vm.send();
    await wrapper.vm.fallback();
    expect(api.create).not.toHaveBeenCalled();
    expect(api.fallback).not.toHaveBeenCalled();
    complete();
    await flushPromises();
    expect(button(wrapper, 'SEND').attributes('disabled')).toBeUndefined();
    mocks.refresh.mockRejectedValueOnce(new Error('Network'));
    await wrapper.vm.load();
    expect(button(wrapper, 'SEND').attributes('disabled')).toBeDefined();
    expect(button(wrapper, 'FALLBACK').attributes('disabled')).toBeDefined();
    await wrapper.vm.send();
    await wrapper.vm.fallback();
    expect(api.create).not.toHaveBeenCalled();
    expect(api.fallback).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});
