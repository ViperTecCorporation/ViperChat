/* global axios */
import ApiClient from './ApiClient';

class InboxMembers extends ApiClient {
  constructor() {
    super('inbox_members', { accountScoped: true });
  }

  update({ inboxId, agentList, memberAttributes }) {
    const payload = { inbox_id: inboxId };
    if (agentList !== undefined) {
      payload.user_ids = agentList;
    }
    if (memberAttributes?.length) {
      payload.member_attributes = memberAttributes;
    }
    // eslint-disable-next-line no-console
    console.log('[InboxMembersAPI] update', {
      inboxId,
      agentCount: agentList?.length,
      memberAttributesCount: memberAttributes?.length,
    });
    return axios.patch(this.url, payload);
  }
}

export default new InboxMembers();
