import { computed, ref, watch, onUnmounted, onMounted } from 'vue';
import { useStore } from 'vuex';
import VoiceAPI from 'dashboard/api/channel/voice/voiceAPIClient';
import TwilioVoiceClient from 'dashboard/api/channel/voice/twilioVoiceClient';
import CustomVoiceClient from 'dashboard/api/channel/voice/customVoiceClient';
import { useCallsStore } from 'dashboard/stores/calls';
import Timer from 'dashboard/helper/Timer';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

export function useCallSession() {
  const callsStore = useCallsStore();
  const store = useStore();
  const isJoining = ref(false);
  const callDuration = ref(0);
  const durationTimer = new Timer(elapsed => {
    callDuration.value = elapsed;
  });

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

  const handleDisconnect = () => callsStore.clearActiveCall();
  const autoRegisterAttempted = ref(false);

  const voiceInboxes = computed(() => {
    const inboxes = store.getters['inboxes/getInboxes'] || [];
    return inboxes.filter(
      inbox =>
        inbox.channel_type === INBOX_TYPES.VOICE && inbox.provider === 'custom'
    );
  });

  onMounted(() => {
    TwilioVoiceClient.addEventListener('call:disconnected', handleDisconnect);
    CustomVoiceClient.addEventListener('call:disconnected', handleDisconnect);
  });

  onUnmounted(() => {
    durationTimer.stop();
    TwilioVoiceClient.removeEventListener('call:disconnected', handleDisconnect);
    CustomVoiceClient.removeEventListener('call:disconnected', handleDisconnect);
  });

  const autoRegisterVoice = async inboxId => {
    try {
      // eslint-disable-next-line no-console
      console.log('[CallSession] autoRegisterVoice start', { inboxId });
      await CustomVoiceClient.initializeDevice(inboxId);
      // eslint-disable-next-line no-console
      console.log('[CallSession] autoRegisterVoice success', { inboxId });
    } catch (error) {
      // eslint-disable-next-line no-console
      console.warn('[CallSession] autoRegisterVoice error', {
        inboxId,
        error,
      });
    }
  };

  watch(
    voiceInboxes,
    inboxes => {
      if (autoRegisterAttempted.value) return;
      const inbox = inboxes?.[0];
      if (!inbox?.id) return;
      autoRegisterAttempted.value = true;
      autoRegisterVoice(inbox.id);
    },
    { immediate: true }
  );

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
    console.log('[CallSession] joinCall start', {
      conversationId,
      inboxId,
      callSid,
    });
    try {
      const voiceClient = resolveVoiceClient(inboxId);
      const device = await voiceClient.initializeDevice(inboxId);
      if (!device) return null;

      const joinResponse = await VoiceAPI.joinConference({
        conversationId,
        inboxId,
        callSid,
      });

      const target = joinResponse?.to || joinResponse?.conference_sid;
      if (!target) return null;

      await voiceClient.joinClientCall({
        to: target,
        conversationId,
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
    resolveVoiceClient(inboxId).endClientCall();
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
  };
}
