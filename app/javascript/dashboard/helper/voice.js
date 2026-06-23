import { CONTENT_TYPES } from 'dashboard/components-next/message/constants';
import { useCallsStore } from 'dashboard/stores/calls';
import types from 'dashboard/store/mutation-types';

export const TERMINAL_STATUSES = [
  'completed',
  'busy',
  'failed',
  'rejected',
  'no-answer',
  'canceled',
  'missed',
  'ended',
];

export const isInbound = direction => direction === 'inbound';

const isVoiceCallMessage = message => {
  return CONTENT_TYPES.VOICE_CALL === message?.content_type;
};

const shouldSkipCall = (callDirection, senderId, currentUserId, callType) => {
  if (callType === 'internal') return false;
  return callDirection === 'outbound' && senderId !== currentUserId;
};

function resolveDirection(callDirection, senderId, currentUserId, callType) {
  if (callType === 'internal' && senderId && senderId !== currentUserId) {
    return 'inbound';
  }
  return callDirection;
}

function extractCallData(message, currentUserId) {
  const contentData = message?.content_attributes?.data || {};
  const callType = contentData.call_type;
  return {
    callSid: contentData.call_sid,
    status: contentData.status,
    callDirection: resolveDirection(
      contentData.call_direction,
      message?.sender?.id,
      currentUserId,
      callType
    ),
    callType,
    inboxId: contentData.voice_inbox_id,
    conversationId: message?.conversation_id,
    senderId: message?.sender?.id,
  };
}

export function handleVoiceCallCreated(message, currentUserId) {
  if (!isVoiceCallMessage(message)) return;

  const { callSid, callDirection, callType, conversationId, senderId, inboxId } =
    extractCallData(message, currentUserId);

  if (shouldSkipCall(callDirection, senderId, currentUserId, callType)) return;

  // eslint-disable-next-line no-console
  console.log('[VoiceHelper] handleVoiceCallCreated', {
    callSid,
    conversationId,
    callDirection,
    callType,
    inboxId,
  });
  const callsStore = useCallsStore();
  callsStore.addCall({
    callSid,
    conversationId,
    callDirection,
    senderId,
    inboxId,
  });
}

export function handleVoiceCallUpdated(commit, message, currentUserId) {
  if (!isVoiceCallMessage(message)) return;

  const { callSid, status, callDirection, callType, conversationId, senderId, inboxId } =
    extractCallData(message, currentUserId);

  // eslint-disable-next-line no-console
  console.log('[VoiceHelper] handleVoiceCallUpdated', {
    callSid,
    conversationId,
    status,
    callDirection,
    callType,
    inboxId,
  });
  const callsStore = useCallsStore();

  callsStore.handleCallStatusChanged({ callSid, status, conversationId });

  const callInfo = { conversationId, callStatus: status };
  commit(types.UPDATE_CONVERSATION_CALL_STATUS, callInfo);
  commit(types.UPDATE_MESSAGE_CALL_STATUS, callInfo);

  const isNewCall =
    status === 'ringing' &&
    !shouldSkipCall(callDirection, senderId, currentUserId, callType);

  if (isNewCall) {
    callsStore.addCall({
      callSid,
      conversationId,
      callDirection,
      senderId,
      inboxId,
    });
  }
}
