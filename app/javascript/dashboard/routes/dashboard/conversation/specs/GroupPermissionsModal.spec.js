import { flushPromises, mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import ConfirmationModal from 'dashboard/components/widgets/modal/ConfirmationModal.vue';
import GroupPermissionsModal from '../GroupPermissionsModal.vue';

const mocks = vi.hoisted(() => ({
  updateGroup: vi.fn(),
  leaveGroup: vi.fn(),
  syncGroup: vi.fn(),
  useAlert: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: mocks.useAlert,
}));

vi.mock('dashboard/api/inbox/conversation', () => ({
  default: {
    updateGroup: mocks.updateGroup,
    leaveGroup: mocks.leaveGroup,
    syncGroup: mocks.syncGroup,
  },
}));

const mountModal = props =>
  mount(GroupPermissionsModal, {
    props: {
      conversationId: 42,
      show: true,
      ...props,
    },
    global: {
      mocks: {
        $t: key => key,
      },
    },
  });

describe('GroupPermissionsModal', () => {
  beforeEach(() => {
    mocks.updateGroup.mockReset();
    mocks.leaveGroup.mockReset();
    mocks.syncGroup.mockReset();
    mocks.useAlert.mockReset();
  });

  it('keeps every permission and save disabled for a non-admin session', () => {
    const wrapper = mountModal({ isSessionAdmin: false });

    wrapper.findAll('input[type="checkbox"]').forEach(checkbox => {
      expect(checkbox.attributes('disabled')).toBeDefined();
    });

    const saveButton = wrapper
      .findAll('button')
      .find(button =>
        button.text().includes('CONVERSATION.GROUP.SAVE_PERMISSIONS')
      );
    expect(saveButton.attributes('disabled')).toBeDefined();

    const leaveButton = wrapper
      .findAll('button')
      .find(button => button.text().includes('CONVERSATION.GROUP.LEAVE'));
    expect(leaveButton.attributes('disabled')).toBeUndefined();
  });

  it('sends all permission fields for an admin session', async () => {
    mocks.updateGroup.mockResolvedValue({
      data: {
        group_announcement: true,
        group_locked: true,
        group_join_approval_mode: 'approval_required',
      },
    });
    const wrapper = mountModal({ isSessionAdmin: true });

    await Promise.all(
      wrapper
        .findAll('input[type="checkbox"]')
        .map(checkbox => checkbox.setValue(true))
    );

    const saveButton = wrapper
      .findAll('button')
      .find(button =>
        button.text().includes('CONVERSATION.GROUP.SAVE_PERMISSIONS')
      );
    await saveButton.trigger('click');
    await flushPromises();

    expect(mocks.updateGroup).toHaveBeenCalledWith({
      conversationId: 42,
      announcement: true,
      locked: true,
      join_approval_mode: 'approval_required',
    });
  });

  it('restores the previous controls when the provider rejects the update', async () => {
    mocks.updateGroup.mockRejectedValue({
      response: {
        status: 404,
        data: { error: 'no supported group changes provided' },
      },
    });
    const wrapper = mountModal({
      isSessionAdmin: true,
      announcement: false,
    });
    const [announcement] = wrapper.findAll('input[type="checkbox"]');
    await announcement.setValue(true);

    const saveButton = wrapper
      .findAll('button')
      .find(button =>
        button.text().includes('CONVERSATION.GROUP.SAVE_PERMISSIONS')
      );
    await saveButton.trigger('click');
    await flushPromises();

    expect(announcement.element.checked).toBe(false);
    expect(mocks.useAlert).toHaveBeenCalledWith(
      'no supported group changes provided'
    );
  });

  it('allows a non-admin session to confirm leaving the group', async () => {
    mocks.leaveGroup.mockResolvedValue({
      data: { group_session_admin: false },
    });
    const wrapper = mountModal({ isSessionAdmin: false });

    const leaveButton = wrapper
      .findAll('button')
      .find(button => button.text().includes('CONVERSATION.GROUP.LEAVE'));
    await leaveButton.trigger('click');
    await nextTick();

    wrapper.findComponent(ConfirmationModal).vm.confirm();
    await flushPromises();

    expect(mocks.leaveGroup).toHaveBeenCalledWith(42);
  });

  it('checks group state without repeating leave after a timeout', async () => {
    mocks.leaveGroup.mockRejectedValue({ code: 'ECONNABORTED' });
    mocks.syncGroup.mockResolvedValue({
      data: {
        id: 42,
        additional_attributes: {
          group_session_removed_at: '2026-07-23T23:00:00Z',
        },
      },
    });
    const wrapper = mountModal({ isSessionAdmin: false });

    const leaveButton = wrapper
      .findAll('button')
      .find(button => button.text().includes('CONVERSATION.GROUP.LEAVE'));
    await leaveButton.trigger('click');
    await nextTick();
    wrapper.findComponent(ConfirmationModal).vm.confirm();
    await flushPromises();

    expect(mocks.leaveGroup).toHaveBeenCalledTimes(1);
    expect(mocks.syncGroup).toHaveBeenCalledWith(42);
    expect(wrapper.emitted('groupLeft')).toHaveLength(1);
  });
});
