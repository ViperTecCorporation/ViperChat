import { defineStore } from 'pinia';
import TwilioVoiceClient from 'dashboard/api/channel/voice/twilioVoiceClient';
import CustomVoiceClient from 'dashboard/api/channel/voice/customVoiceClient';
import { TERMINAL_STATUSES } from 'dashboard/helper/voice';

export const useCallsStore = defineStore('calls', {
  state: () => ({
    calls: [],
  }),

  getters: {
    activeCall: state => state.calls.find(call => call.isActive) || null,
    hasActiveCall: state => state.calls.some(call => call.isActive),
    incomingCalls: state => state.calls.filter(call => !call.isActive),
    hasIncomingCall: state => state.calls.some(call => !call.isActive),
  },

  actions: {
    handleCallStatusChanged({ callSid, status }) {
      // eslint-disable-next-line no-console
      console.log('[CallsStore] handleCallStatusChanged', { callSid, status });
      if (TERMINAL_STATUSES.includes(status)) {
        this.removeCall(callSid);
      }
    },

    addCall(callData) {
      if (!callData?.callSid) return;
      const exists = this.calls.some(call => call.callSid === callData.callSid);
      if (exists) return;

      // eslint-disable-next-line no-console
      console.log('[CallsStore] addCall', {
        callSid: callData.callSid,
        conversationId: callData.conversationId,
        inboxId: callData.inboxId,
        callDirection: callData.callDirection,
      });
      this.calls.push({
        ...callData,
        isActive: false,
      });
    },

    removeCall(callSid) {
      const callToRemove = this.calls.find(c => c.callSid === callSid);
      // eslint-disable-next-line no-console
      console.log('[CallsStore] removeCall', {
        callSid,
        wasActive: !!callToRemove?.isActive,
      });
      if (callToRemove?.isActive) {
        TwilioVoiceClient.endClientCall();
        CustomVoiceClient.endClientCall();
      }
      this.calls = this.calls.filter(c => c.callSid !== callSid);
    },

    setCallActive(callSid) {
      // eslint-disable-next-line no-console
      console.log('[CallsStore] setCallActive', { callSid });
      this.calls = this.calls.map(call => ({
        ...call,
        isActive: call.callSid === callSid,
      }));
    },

    clearActiveCall() {
      // eslint-disable-next-line no-console
      console.log('[CallsStore] clearActiveCall');
      TwilioVoiceClient.endClientCall();
      CustomVoiceClient.endClientCall();
      this.calls = this.calls.filter(call => !call.isActive);
    },

    dismissCall(callSid) {
      // eslint-disable-next-line no-console
      console.log('[CallsStore] dismissCall', { callSid });
      this.calls = this.calls.filter(call => call.callSid !== callSid);
    },
  },
});
