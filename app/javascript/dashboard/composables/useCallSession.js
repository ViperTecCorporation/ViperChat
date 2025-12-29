import { computed, ref, watch, onUnmounted, onMounted } from 'vue';
import { useStore } from 'vuex';
import VoiceAPI from 'dashboard/api/channel/voice/voiceAPIClient';
import TwilioVoiceClient from 'dashboard/api/channel/voice/twilioVoiceClient';
import CustomVoiceClient from 'dashboard/api/channel/voice/customVoiceClient';
import { useCallsStore } from 'dashboard/stores/calls';
import Timer from 'dashboard/helper/Timer';

export function useCallSession() {
  const callsStore = useCallsStore();
  const store = useStore();
  const isJoining = ref(false);
  const callDuration = ref(0);
  const durationTimer = new Timer(elapsed => {
    callDuration.value = elapsed;
  });
  const joinTimeoutMs = 60000;

  const activeCall = computed(() => callsStore.activeCall);
  const incomingCalls = computed(() => callsStore.incomingCalls);
  const hasActiveCall = computed(() => callsStore.hasActiveCall);

  watch(
    hasActiveCall,
    active => {
      if (active) {
        durationTimer.start();
      } else {
        durationTimer.stop();
        callDuration.value = 0;
      }
    },
    { immediate: true }
  );

    const handleDisconnect = event => {
      const detail = event?.detail || {};
      const { callSid } = detail;
      if (callSid) {
        callsStore.removeCall(callSid);
        return;
      }
      callsStore.clearActiveCall();
    };
  const handleIncoming = event => {
    const detail = event?.detail || {};
    const { callSid, conversationId, inboxId } = detail;
    if (!callSid || !conversationId) return;

    callsStore.addCall({
      callSid,
      conversationId,
      inboxId,
      callDirection: 'inbound',
    });
  };
  const handleInviteFailed = async event => {
    const detail = event?.detail || {};
    const { callSid, conversationId, inboxId, error } = detail;
    if (!callSid || !conversationId || !inboxId) return;

    // eslint-disable-next-line no-console
    console.error('[CallSession] invite failed', {
      callSid,
      conversationId,
      inboxId,
      error,
    });

    try {
      await VoiceAPI.updateCallStatus({
        conversationId,
        inboxId,
        callSid,
        callStatus: 'failed',
        reason: error?.message || 'invite_failed',
        timestamp: Math.floor(Date.now() / 1000),
      });
    } catch (statusError) {
      // eslint-disable-next-line no-console
      console.error('[CallSession] updateCallStatus failed', {
        conversationId,
        inboxId,
        callSid,
        error: statusError,
      });
    }

    resolveVoiceClient(inboxId)?.endClientCall?.();
    callsStore.removeCall(callSid);
    durationTimer.stop();
  };

  onMounted(() => {
    TwilioVoiceClient.addEventListener('call:disconnected', handleDisconnect);
    CustomVoiceClient.addEventListener('call:disconnected', handleDisconnect);
    CustomVoiceClient.addEventListener('call:incoming', handleIncoming);
    CustomVoiceClient.addEventListener('call:invite_failed', handleInviteFailed);
  });

  onUnmounted(() => {
    durationTimer.stop();
    TwilioVoiceClient.removeEventListener('call:disconnected', handleDisconnect);
    CustomVoiceClient.removeEventListener('call:disconnected', handleDisconnect);
    CustomVoiceClient.removeEventListener('call:incoming', handleIncoming);
    CustomVoiceClient.removeEventListener(
      'call:invite_failed',
      handleInviteFailed
    );
  });

  const resolveInboxProvider = inboxId => {
    if (!inboxId) return 'twilio';
    const inbox = store.getters['inboxes/getInboxById'](inboxId);
    // eslint-disable-next-line no-console
    console.log('[CallSession] resolveInboxProvider', {
      inboxId,
      provider: inbox?.provider || 'twilio',
    });
    return inbox?.provider || 'twilio';
  };

  const resolveVoiceClient = inboxId => {
    return resolveInboxProvider(inboxId) === 'custom'
      ? CustomVoiceClient
      : TwilioVoiceClient;
  };

  const endCall = async ({ conversationId, inboxId }) => {
    // eslint-disable-next-line no-console
    console.log('[CallSession] endCall', { conversationId, inboxId });
    await VoiceAPI.leaveConference(inboxId, conversationId);
    resolveVoiceClient(inboxId).endClientCall();
    durationTimer.stop();
    callsStore.clearActiveCall();
  };

  const joinCall = async ({ conversationId, inboxId, callSid }) => {
    if (isJoining.value) return null;

    isJoining.value = true;
    // eslint-disable-next-line no-console
    console.log('[CallSession] joinCall start', { conversationId, inboxId, callSid });
    try {
      const voiceClient = resolveVoiceClient(inboxId);
      const device = await voiceClient.initializeDevice(inboxId);
      if (!device) return null;

      const joinResponse = await VoiceAPI.joinConference({
        conversationId,
        inboxId,
        callSid,
      });

      const acceptedIncoming = await voiceClient.acceptIncomingCall?.({
        callSid,
        conversationId,
        inboxId,
      });

      if (acceptedIncoming) {
        callsStore.setCallActive(callSid);
        durationTimer.start();
        return { conferenceSid: joinResponse?.conference_sid };
      }

      const target = joinResponse?.to || joinResponse?.conference_sid;
      if (!target) return null;

      const provider = resolveInboxProvider(inboxId);
      if (provider === 'custom') {
        voiceClient.joinClientCall({
          to: target,
          conversationId,
          callSid,
        });
        callsStore.setCallActive(callSid);
        durationTimer.start();
        // eslint-disable-next-line no-console
        console.log('[CallSession] joinCall initiated', {
          conversationId,
          inboxId,
          callSid,
          provider,
          conferenceSid: joinResponse?.conference_sid,
        });
        return { conferenceSid: joinResponse?.conference_sid };
      }

      const joinPromise = voiceClient.joinClientCall({
        to: target,
        conversationId,
        callSid,
      });
      await new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          reject(new Error('joinClientCall timeout'));
        }, joinTimeoutMs);
        joinPromise
          .then(result => {
            clearTimeout(timer);
            resolve(result);
          })
          .catch(error => {
            clearTimeout(timer);
            reject(error);
          });
      });

      callsStore.setCallActive(callSid);
      durationTimer.start();

      // eslint-disable-next-line no-console
      console.log('[CallSession] joinCall success', {
        conversationId,
        inboxId,
        callSid,
        conferenceSid: joinResponse?.conference_sid,
      });
      return { conferenceSid: joinResponse?.conference_sid };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('Failed to join call:', error);
      const failureReason = error?.message || 'join_failed';
      if (conversationId && inboxId && callSid) {
        try {
          await VoiceAPI.updateCallStatus({
            conversationId,
            inboxId,
            callSid,
            callStatus: 'failed',
            reason: failureReason,
            timestamp: Math.floor(Date.now() / 1000),
          });
        } catch (statusError) {
          // eslint-disable-next-line no-console
          console.error('[CallSession] updateCallStatus failed', {
            conversationId,
            inboxId,
            callSid,
            error: statusError,
          });
        }
      }
      const voiceClient = resolveVoiceClient(inboxId);
      voiceClient?.endClientCall?.();
      if (callSid) {
        callsStore.removeCall(callSid);
      } else {
        callsStore.clearActiveCall();
      }
      durationTimer.stop();
      return null;
    } finally {
      isJoining.value = false;
    }
  };

  const rejectIncomingCall = callSid => {
    const call = callsStore.calls.find(item => item.callSid === callSid);
    const conversation = store.getters.getConversationById(call?.conversationId);
    const inboxId = call?.inboxId || conversation?.inbox_id;
    // eslint-disable-next-line no-console
    console.log('[CallSession] rejectIncomingCall', {
      callSid,
      conversationId: call?.conversationId,
      inboxId,
    });
    const voiceClient = resolveVoiceClient(inboxId);
    if (typeof voiceClient.rejectIncomingCall === 'function') {
      voiceClient.rejectIncomingCall({ callSid });
    } else {
      voiceClient.endClientCall();
    }
    callsStore.dismissCall(callSid);
  };

  const transferCall = async ({
    conversationId,
    inboxId,
    targetAgentId,
    callSid,
  }) => {
    // eslint-disable-next-line no-console
    console.log('[CallSession] transferCall', {
      conversationId,
      inboxId,
      targetAgentId,
      callSid,
    });
    const response = await VoiceAPI.transferCall({
      conversationId,
      inboxId,
      targetAgentId,
      callSid,
    });

    if (response?.mode === 'sip_refer' && response?.refer_to) {
      // eslint-disable-next-line no-console
      console.log('[CallSession] transferCall sip_refer', {
        inboxId,
        referTo: response.refer_to,
      });
      resolveVoiceClient(inboxId).transferCall({
        referTo: response.refer_to,
      });
    }

    return response;
  };

  const sendDtmf = ({ inboxId, digits }) => {
    const voiceClient = resolveVoiceClient(inboxId);
    const success = voiceClient?.sendDtmf?.(digits);
    if (!success) {
      // eslint-disable-next-line no-console
      console.warn('[CallSession] sendDtmf failed', { inboxId, digits });
    }
    return success;
  };

  const dismissCall = callSid => {
    // eslint-disable-next-line no-console
    console.log('[CallSession] dismissCall', { callSid });
    callsStore.dismissCall(callSid);
  };

  const formattedCallDuration = computed(() => {
    const minutes = Math.floor(callDuration.value / 60);
    const seconds = callDuration.value % 60;
    return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
  });

  return {
    activeCall,
    incomingCalls,
    hasActiveCall,
    isJoining,
    formattedCallDuration,
    joinCall,
    endCall,
    rejectIncomingCall,
    dismissCall,
    transferCall,
    sendDtmf,
  };
}
