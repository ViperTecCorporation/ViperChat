/* global axios */
import ApiClient from '../ApiClient';

class ConversationApi extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  get({
    inboxId,
    status,
    assigneeType,
    page,
    labels,
    teamId,
    conversationType,
    sortBy,
    updatedWithin,
  }) {
    return axios.get(this.url, {
      params: {
        inbox_id: inboxId,
        team_id: teamId,
        status,
        assignee_type: assigneeType,
        page,
        labels,
        conversation_type: conversationType,
        sort_by: sortBy,
        updated_within: updatedWithin,
      },
    });
  }

  filter(payload) {
    return axios.post(`${this.url}/filter`, payload.queryData, {
      params: {
        page: payload.page,
      },
    });
  }

  search({ q }) {
    return axios.get(`${this.url}/search`, {
      params: {
        q,
        page: 1,
      },
    });
  }

  toggleStatus({ conversationId, status, snoozedUntil = null }) {
    return axios.post(`${this.url}/${conversationId}/toggle_status`, {
      status,
      snoozed_until: snoozedUntil,
    });
  }

  togglePriority({ conversationId, priority }) {
    return axios.post(`${this.url}/${conversationId}/toggle_priority`, {
      priority,
    });
  }

  assignAgent({ conversationId, agentId }) {
    return axios.post(`${this.url}/${conversationId}/assignments`, {
      assignee_id: agentId,
    });
  }

  assignTeam({ conversationId, teamId }) {
    const params = { team_id: teamId };
    return axios.post(`${this.url}/${conversationId}/assignments`, params);
  }

  markMessageRead({ id }) {
    return axios.post(`${this.url}/${id}/update_last_seen`);
  }

  markMessagesUnread({ id }) {
    return axios.post(`${this.url}/${id}/unread`);
  }

  toggleTyping({ conversationId, status, isPrivate }) {
    return axios.post(`${this.url}/${conversationId}/toggle_typing_status`, {
      typing_status: status,
      is_private: isPrivate,
    });
  }

  mute(conversationId) {
    return axios.post(`${this.url}/${conversationId}/mute`);
  }

  unmute(conversationId) {
    return axios.post(`${this.url}/${conversationId}/unmute`);
  }

  meta({ inboxId, status, assigneeType, labels, teamId, conversationType }) {
    return axios.get(`${this.url}/meta`, {
      params: {
        inbox_id: inboxId,
        status,
        assignee_type: assigneeType,
        labels,
        team_id: teamId,
        conversation_type: conversationType,
      },
    });
  }

  sendEmailTranscript({ conversationId, email }) {
    return axios.post(`${this.url}/${conversationId}/transcript`, { email });
  }

  updateCustomAttributes({ conversationId, customAttributes }) {
    return axios.post(`${this.url}/${conversationId}/custom_attributes`, {
      custom_attributes: customAttributes,
    });
  }

  fetchParticipants(conversationId) {
    return axios.get(`${this.url}/${conversationId}/participants`);
  }

  fetchGroupContacts(conversationId, page = 1, query = '') {
    return axios.get(`${this.url}/${conversationId}/group_contacts`, {
      params: { page, query },
    });
  }

  removeGroupContacts({ conversationId, participants }) {
    return axios.delete(`${this.url}/${conversationId}/group_contacts`, {
      data: { participants },
    });
  }

  addGroupContacts({ conversationId, participants }) {
    return axios.post(`${this.url}/${conversationId}/group_contacts`, {
      participants,
    });
  }

  createGroup({
    inboxId,
    subject,
    description,
    participants,
    joinApprovalMode,
  }) {
    return axios.post(`${this.url}/groups`, {
      inbox_id: inboxId,
      subject,
      description,
      participants,
      join_approval_mode: joinApprovalMode,
    });
  }

  fetchGroup(conversationId) {
    return axios.get(`${this.url}/${conversationId}/group`);
  }

  updateGroup({ conversationId, ...params }) {
    return axios.patch(`${this.url}/${conversationId}/group`, params);
  }

  syncGroup(conversationId) {
    return axios.post(`${this.url}/${conversationId}/group/sync`);
  }

  fetchGroupInviteLink(conversationId) {
    return axios.get(`${this.url}/${conversationId}/group/invite_link`);
  }

  resetGroupInviteLink(conversationId) {
    return axios.post(`${this.url}/${conversationId}/group/invite_link/reset`);
  }

  fetchGroupJoinRequests(conversationId) {
    return axios.get(`${this.url}/${conversationId}/group/join_requests`);
  }

  approveGroupJoinRequests({ conversationId, participants }) {
    return axios.post(`${this.url}/${conversationId}/group/join_requests`, {
      participants,
    });
  }

  rejectGroupJoinRequests({ conversationId, participants }) {
    return axios.delete(`${this.url}/${conversationId}/group/join_requests`, {
      data: { participants },
    });
  }

  updateParticipants({ conversationId, userIds }) {
    return axios.patch(`${this.url}/${conversationId}/participants`, {
      user_ids: userIds,
    });
  }

  getAllAttachments(conversationId, page = 1) {
    return axios.get(`${this.url}/${conversationId}/attachments`, {
      params: { page },
    });
  }

  deleteAttachments(conversationId, payload) {
    return axios.delete(`${this.url}/${conversationId}/attachments`, {
      data: payload,
    });
  }

  getInboxAssistant(conversationId) {
    return axios.get(`${this.url}/${conversationId}/inbox_assistant`);
  }

  delete(conversationId) {
    return axios.delete(`${this.url}/${conversationId}`);
  }
}

export default new ConversationApi();
