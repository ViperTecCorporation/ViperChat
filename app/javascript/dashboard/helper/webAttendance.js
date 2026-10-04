export const messageDestination = message =>
  message.delivery_destination || 'channel';

export const filterMessagesByDestination = (messages, destination) =>
  messages.filter(
    message =>
      message.private ||
      message.message_type === 2 ||
      message.message_type === 'activity' ||
      messageDestination(message) === destination
  );

export const attendanceDraftKey = (conversationId, replyType, destination) => {
  const base = `draft-${conversationId}-${replyType}`;
  return replyType === 'NOTE' || destination !== 'web' ? base : `${base}-web`;
};
export const supportsWebAttendance = inbox =>
  inbox?.channel_type === 'Channel::Whatsapp' &&
  ['unoapi', 'whatsapp_cloud'].includes(inbox.provider);

export const webAttendanceLimits = provider => ({
  invitation: provider === 'whatsapp_cloud' ? 1024 : 4096,
  button: provider === 'whatsapp_cloud' ? 20 : 60,
});
