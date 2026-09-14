const attachmentTranscription = attachment =>
  attachment?.transcribedText ||
  attachment?.transcribed_text ||
  attachment?.meta?.transcribedText ||
  attachment?.meta?.transcribed_text;

const attachmentFileType = attachment =>
  attachment?.fileType || attachment?.file_type;

const attachmentContentKeys = {
  image: 'CHAT_LIST.ATTACHMENTS.image.CONTENT',
  audio: 'CHAT_LIST.ATTACHMENTS.audio.CONTENT',
  video: 'CHAT_LIST.ATTACHMENTS.video.CONTENT',
  file: 'CHAT_LIST.ATTACHMENTS.file.CONTENT',
  location: 'CHAT_LIST.ATTACHMENTS.location.CONTENT',
  ig_reel: 'CHAT_LIST.ATTACHMENTS.ig_reel.CONTENT',
  fallback: 'CHAT_LIST.ATTACHMENTS.fallback.CONTENT',
  contact: 'CHAT_LIST.ATTACHMENTS.contact.CONTENT',
  embed: 'CHAT_LIST.ATTACHMENTS.embed.CONTENT',
};

export const isEmptyReplyMessage = message => {
  if (!message) return false;
  const attributes =
    message.content_attributes || message.contentAttributes || {};
  const type = message.content_type ?? message.contentType;
  return (
    (!type || type === 'text') &&
    !message.content?.trim() &&
    !message.attachments?.length &&
    Boolean(attributes.in_reply_to || attributes.inReplyTo) &&
    !attributes.deleted &&
    !attributes.is_unsupported &&
    !attributes.isUnsupported
  );
};

export const getMessagePreviewContent = ({
  message = {},
  subject,
  t,
  emptyMessage,
}) => {
  const attachment = message.attachments?.[0];
  const transcription = attachmentTranscription(attachment);

  if (subject || message.content || transcription) {
    return subject || message.content || transcription;
  }

  const fileType = attachmentFileType(attachment);
  const attachmentContentKey = attachmentContentKeys[fileType];
  if (!attachmentContentKey) return emptyMessage || t('CHAT_LIST.NO_CONTENT');

  // The key is constrained by attachmentContentKeys above.
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  return t(attachmentContentKey);
};
