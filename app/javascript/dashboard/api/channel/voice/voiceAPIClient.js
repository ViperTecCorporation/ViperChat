/* global axios */
import ApiClient from '../../ApiClient';
import ContactsAPI from '../../contacts';

class VoiceAPI extends ApiClient {
  constructor() {
    super('voice', { accountScoped: true });
  }

  // eslint-disable-next-line class-methods-use-this
  initiateCall(contactId, inboxId) {
    // eslint-disable-next-line no-console
    console.log('[VoiceAPI] initiateCall request', { contactId, inboxId });
    return ContactsAPI.initiateCall(contactId, inboxId)
      .then(r => {
        const data = r.data;
        // eslint-disable-next-line no-console
        console.log('[VoiceAPI] initiateCall success', {
          contactId,
          inboxId,
          hasCallSid: !!data?.call_sid,
        });
        return data;
      })
      .catch(error => {
        // eslint-disable-next-line no-console
        console.error('[VoiceAPI] initiateCall error', { contactId, inboxId, error });
        throw error;
      });
  }

  initiateCallByPhone(phoneNumber, inboxId) {
    // eslint-disable-next-line no-console
    console.log('[VoiceAPI] initiateCallByPhone request', {
      phoneNumber,
      inboxId,
    });
    return ContactsAPI.initiateCallByPhone(phoneNumber, inboxId)
      .then(r => {
        const data = r.data;
        // eslint-disable-next-line no-console
        console.log('[VoiceAPI] initiateCallByPhone success', {
          phoneNumber,
          inboxId,
          hasCallSid: !!data?.call_sid,
        });
        return data;
      })
      .catch(error => {
        // eslint-disable-next-line no-console
        console.error('[VoiceAPI] initiateCallByPhone error', {
          phoneNumber,
          inboxId,
          error,
        });
        throw error;
      });
  }

  leaveConference(inboxId, conversationId) {
    // eslint-disable-next-line no-console
    console.log('[VoiceAPI] leaveConference request', { inboxId, conversationId });
    return axios
      .delete(`${this.baseUrl()}/inboxes/${inboxId}/conference`, {
        params: { conversation_id: conversationId },
      })
      .then(r => {
        const data = r.data;
        // eslint-disable-next-line no-console
        console.log('[VoiceAPI] leaveConference success', {
          inboxId,
          conversationId,
          status: data?.status,
        });
        return data;
      })
      .catch(error => {
        // eslint-disable-next-line no-console
        console.error('[VoiceAPI] leaveConference error', { inboxId, conversationId, error });
        throw error;
      });
  }

  joinConference({ conversationId, inboxId, callSid }) {
    // eslint-disable-next-line no-console
    console.log('[VoiceAPI] joinConference request', {
      inboxId,
      conversationId,
      callSid,
    });
    return axios
      .post(`${this.baseUrl()}/inboxes/${inboxId}/conference`, {
        conversation_id: conversationId,
        call_sid: callSid,
      })
      .then(r => {
        const data = r.data;
        // eslint-disable-next-line no-console
        console.log('[VoiceAPI] joinConference success', {
          inboxId,
          conversationId,
          callSid,
          provider: data?.provider,
          hasTarget: !!(data?.to || data?.conference_sid),
        });
        return data;
      })
      .catch(error => {
        // eslint-disable-next-line no-console
        console.error('[VoiceAPI] joinConference error', {
          inboxId,
          conversationId,
          callSid,
          error,
        });
        throw error;
      });
  }

  notifyIncomingCall({ inboxId, callSid, fromNumber }) {
    // eslint-disable-next-line no-console
    console.log('[VoiceAPI] notifyIncomingCall request', {
      inboxId,
      callSid,
      fromNumber,
    });
    return axios
      .post(`${this.baseUrl()}/inboxes/${inboxId}/conference/incoming`, {
        call_sid: callSid,
        from_number: fromNumber,
      })
      .then(r => {
        const data = r.data;
        // eslint-disable-next-line no-console
        console.log('[VoiceAPI] notifyIncomingCall success', {
          inboxId,
          conversationId: data?.conversation_id,
          callSid: data?.call_sid,
        });
        return data;
      })
      .catch(error => {
        // eslint-disable-next-line no-console
        console.error('[VoiceAPI] notifyIncomingCall error', {
          inboxId,
          callSid,
          error,
        });
        throw error;
      });
  }

  updateCallStatus({
    conversationId,
    inboxId,
    callSid,
    callStatus,
    reason,
    timestamp,
  }) {
    // eslint-disable-next-line no-console
    console.log('[VoiceAPI] updateCallStatus request', {
      inboxId,
      conversationId,
      callSid,
      callStatus,
      reason,
    });
    return axios
      .post(`${this.baseUrl()}/inboxes/${inboxId}/conference/status`, {
        conversation_id: conversationId,
        call_sid: callSid,
        call_status: callStatus,
        reason,
        timestamp,
      })
      .then(r => {
        const data = r.data;
        // eslint-disable-next-line no-console
        console.log('[VoiceAPI] updateCallStatus success', {
          inboxId,
          conversationId,
          callSid,
          callStatus: data?.call_status,
        });
        return data;
      })
      .catch(error => {
        // eslint-disable-next-line no-console
        console.error('[VoiceAPI] updateCallStatus error', {
          inboxId,
          conversationId,
          callSid,
          callStatus,
          error,
        });
        throw error;
      });
  }

  transferCall({ conversationId, inboxId, targetAgentId, callSid }) {
    // eslint-disable-next-line no-console
    console.log('[VoiceAPI] transferCall request', {
      inboxId,
      conversationId,
      targetAgentId,
      callSid,
    });
    return axios
      .post(`${this.baseUrl()}/inboxes/${inboxId}/conference/transfer`, {
        conversation_id: conversationId,
        target_agent_id: targetAgentId,
        call_sid: callSid,
      })
      .then(r => {
        const data = r.data;
        // eslint-disable-next-line no-console
        console.log('[VoiceAPI] transferCall success', {
          inboxId,
          conversationId,
          targetAgentId,
          callSid,
          mode: data?.mode,
          status: data?.status,
          hasReferTo: !!data?.refer_to,
        });
        return data;
      })
      .catch(error => {
        // eslint-disable-next-line no-console
        console.error('[VoiceAPI] transferCall error', {
          inboxId,
          conversationId,
          targetAgentId,
          callSid,
          error,
        });
        throw error;
      });
  }

  getToken(inboxId) {
    if (!inboxId) return Promise.reject(new Error('Inbox ID is required'));
    // eslint-disable-next-line no-console
    console.log('[VoiceAPI] getToken request', { inboxId });
    return axios
      .get(`${this.baseUrl()}/inboxes/${inboxId}/conference/token`)
      .then(r => {
        const data = r.data;
        // eslint-disable-next-line no-console
        console.log('[VoiceAPI] getToken success', {
          inboxId,
          provider: data?.provider,
          authType: data?.auth_type,
          hasToken: !!data?.token,
          hasPassword: !!data?.password,
          hasWebrtcConfig: !!data?.webrtc,
        });
        return data;
      })
      .catch(error => {
        // eslint-disable-next-line no-console
        console.error('[VoiceAPI] getToken error', { inboxId, error });
        throw error;
      });
  }
}

export default new VoiceAPI();
