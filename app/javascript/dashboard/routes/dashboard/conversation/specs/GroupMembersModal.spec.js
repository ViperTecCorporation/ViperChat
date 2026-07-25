import { flushPromises, mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import ConfirmationModal from 'dashboard/components/widgets/modal/ConfirmationModal.vue';
import GroupMembersModal from '../GroupMembersModal.vue';

const mocks = vi.hoisted(() => ({
  fetchGroupContacts: vi.fn(),
  updateGroupContactRoles: vi.fn(),
  useAlert: vi.fn(),
  dispatch: vi.fn(),
  push: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 } }),
  useRouter: () => ({ push: mocks.push }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: mocks.useAlert,
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: mocks.dispatch }),
}));

vi.mock('dashboard/api/inbox/conversation', () => ({
  default: {
    fetchGroupContacts: mocks.fetchGroupContacts,
    updateGroupContactRoles: mocks.updateGroupContactRoles,
  },
}));

const member = {
  id: 7,
  participant_identifier: '123456789012345@lid',
  session_participant: false,
  metadata: {
    user_id: '123456789012345@lid',
    wa_id: '556699999999',
    is_admin: false,
    role: 'member',
  },
  contact: {
    id: 9,
    name: 'Maria',
    bsuid: '123456789012345@lid',
    phone_number: '+556699999999',
  },
};

const mountModal = async ({
  isSessionAdmin = true,
  payload = [member],
} = {}) => {
  mocks.fetchGroupContacts.mockResolvedValue({
    data: { payload, meta: { count: payload.length } },
  });
  const wrapper = mount(GroupMembersModal, {
    props: {
      conversationId: 42,
      show: false,
      isSessionAdmin,
    },
    global: {
      mocks: { $t: key => key },
      stubs: {
        Avatar: true,
        ComposeConversation: {
          template:
            '<div class="compose-conversation"><slot name="trigger" /></div>',
        },
      },
    },
  });

  await wrapper.setProps({ show: true });
  await flushPromises();
  return wrapper;
};

describe('GroupMembersModal', () => {
  beforeEach(() => {
    Object.values(mocks).forEach(mockFn => mockFn.mockReset());
  });

  it('does not show role actions to a non-admin session', async () => {
    const wrapper = await mountModal({ isSessionAdmin: false });

    expect(
      wrapper.find('[aria-label="CONVERSATION.GROUP.PROMOTE_ADMIN"]').exists()
    ).toBe(false);
  });

  it('promotes using user_id and wa_id before refreshing the member list', async () => {
    mocks.updateGroupContactRoles.mockResolvedValue({
      data: { promoted: ['123456789012345@lid'], failed: [] },
    });
    const wrapper = await mountModal();

    const promoteButton = wrapper.find(
      '[aria-label="CONVERSATION.GROUP.PROMOTE_ADMIN"]'
    );
    expect(promoteButton.element.nextElementSibling).toBe(
      wrapper.find('.compose-conversation').element
    );

    await promoteButton.trigger('click');
    await flushPromises();

    expect(mocks.updateGroupContactRoles).toHaveBeenCalledWith({
      conversationId: 42,
      action: 'promote',
      participants: [
        {
          user_id: '123456789012345@lid',
          wa_id: '556699999999',
        },
      ],
      confirmedSelfDemote: false,
    });
    expect(mocks.fetchGroupContacts).toHaveBeenCalledTimes(2);
  });

  it('offers demotion instead of promotion for an existing admin', async () => {
    const admin = {
      ...member,
      metadata: { ...member.metadata, is_admin: true, role: 'admin' },
    };
    const wrapper = await mountModal({ payload: [admin] });

    expect(
      wrapper.find('[aria-label="CONVERSATION.GROUP.PROMOTE_ADMIN"]').exists()
    ).toBe(false);
    expect(
      wrapper.find('[aria-label="CONVERSATION.GROUP.DEMOTE_ADMIN"]').exists()
    ).toBe(true);
  });

  it('requires confirmation and marks an explicit self demotion', async () => {
    const sessionAdmin = {
      ...member,
      session_participant: true,
      metadata: { ...member.metadata, is_admin: true, role: 'admin' },
    };
    mocks.updateGroupContactRoles.mockResolvedValue({
      data: { demoted: ['123456789012345@lid'], failed: [] },
    });
    const wrapper = await mountModal({ payload: [sessionAdmin] });

    await wrapper
      .find('[aria-label="CONVERSATION.GROUP.DEMOTE_ADMIN"]')
      .trigger('click');
    await nextTick();
    expect(mocks.updateGroupContactRoles).not.toHaveBeenCalled();

    wrapper.findComponent(ConfirmationModal).vm.confirm();
    await flushPromises();

    expect(mocks.updateGroupContactRoles).toHaveBeenCalledWith(
      expect.objectContaining({ confirmedSelfDemote: true })
    );
  });

  it('reports failed participants individually without refreshing the list', async () => {
    mocks.updateGroupContactRoles.mockResolvedValue({
      data: {
        promoted: [],
        failed: [
          {
            user_id: '123456789012345@lid',
            error: 'participant_not_found',
          },
        ],
      },
    });
    const wrapper = await mountModal();

    await wrapper
      .find('[aria-label="CONVERSATION.GROUP.PROMOTE_ADMIN"]')
      .trigger('click');
    await flushPromises();

    expect(mocks.useAlert).toHaveBeenCalledTimes(1);
    expect(mocks.fetchGroupContacts).toHaveBeenCalledTimes(1);
  });

  it('keeps a successful role change when the provider response is contradictory and the refresh fails', async () => {
    mocks.updateGroupContactRoles.mockResolvedValue({
      data: {
        promoted: ['123456789012345@lid'],
        failed: [
          {
            wa_id: '556699999999',
            error: 'provider_error',
          },
        ],
      },
    });
    const wrapper = await mountModal();
    mocks.fetchGroupContacts.mockRejectedValueOnce(
      new Error('members refresh failed')
    );

    await wrapper
      .find('[aria-label="CONVERSATION.GROUP.PROMOTE_ADMIN"]')
      .trigger('click');
    await flushPromises();

    expect(mocks.useAlert).toHaveBeenCalledTimes(1);
    expect(mocks.useAlert).toHaveBeenCalledWith(
      'CONVERSATION.GROUP.PROMOTE_SUCCESS'
    );
    expect(wrapper.emitted('memberRoleUpdated')).toHaveLength(1);
  });
});
