import InboxMembersAPI from '../../api/inboxMembers';

export const actions = {
  get(_, { inboxId }) {
    // eslint-disable-next-line no-console
    console.log('[InboxMembersStore] get', { inboxId });
    return InboxMembersAPI.show(inboxId);
  },
  create(_, { inboxId, agentList }) {
    // eslint-disable-next-line no-console
    console.log('[InboxMembersStore] create', {
      inboxId,
      agentCount: agentList?.length,
    });
    return InboxMembersAPI.update({ inboxId, agentList });
  },
  updateCredentials(_, { inboxId, memberAttributes }) {
    // eslint-disable-next-line no-console
    console.log('[InboxMembersStore] updateCredentials', {
      inboxId,
      memberAttributesCount: memberAttributes?.length,
    });
    return InboxMembersAPI.update({ inboxId, memberAttributes });
  },
};

export default {
  namespaced: true,
  actions,
};
