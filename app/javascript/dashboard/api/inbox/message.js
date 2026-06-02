/* eslint no-console: 0 */
/* global axios */
import ApiClient from '../ApiClient';

export const buildCreatePayload = ({
  message,
  isPrivate,
  contentType,
  contentAttributes,
  echoId,
  files,
  ccEmails = '',
  bccEmails = '',
  toEmails = '',
  templateParams,
  isVoiceMessage = false,
}) => {
  let payload;
  if (files && files.length !== 0) {
    payload = new FormData();
    if (message) {
      payload.append('content', message);
    }
    files.forEach(file => {
      payload.append('attachments[]', file);
    });
    payload.append('private', isPrivate);
    payload.append('echo_id', echoId);
    if (contentType) {
      payload.append('content_type', contentType);
    }
    payload.append('cc_emails', ccEmails);
    payload.append('bcc_emails', bccEmails);

    if (toEmails) {
      payload.append('to_emails', toEmails);
    }
    if (contentAttributes) {
      payload.append('content_attributes', JSON.stringify(contentAttributes));
    }
    if (isVoiceMessage) {
      payload.append('is_voice_message', true);
    }
  } else {
    payload = {
      content: message,
      private: isPrivate,
      echo_id: echoId,
      content_type: contentType,
      content_attributes: contentAttributes,
      cc_emails: ccEmails,
      bcc_emails: bccEmails,
      to_emails: toEmails,
      template_params: templateParams,
    };
  }
  return payload;
};

class MessageApi extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  create({
    conversationId,
    message,
    private: isPrivate,
    contentAttributes,
    content_attributes: contentAttributesSnake,
    contentType,
    content_type: contentTypeSnake,
    echo_id: echoId,
    files,
    ccEmails = '',
    bccEmails = '',
    toEmails = '',
    templateParams,
    isVoiceMessage = false,
  }) {
    const normalizedContentAttributes =
      contentAttributes || contentAttributesSnake;
    const normalizedContentType = contentType || contentTypeSnake;
    return axios({
      method: 'post',
      url: `${this.url}/${conversationId}/messages`,
      data: buildCreatePayload({
        message,
        isPrivate,
        contentAttributes: normalizedContentAttributes,
        contentType: normalizedContentType,
        echoId,
        files,
        ccEmails,
        bccEmails,
        toEmails,
        templateParams,
        isVoiceMessage,
      }),
    });
  }

  delete(conversationID, messageId) {
    return axios.delete(`${this.url}/${conversationID}/messages/${messageId}`);
  }

  retry(conversationID, messageId) {
    return axios.post(
      `${this.url}/${conversationID}/messages/${messageId}/retry`
    );
  }

  getPreviousMessages({ conversationId, after, before }) {
    const params = { before };
    if (after && Number(after) !== Number(before)) {
      params.after = after;
    }
    return axios.get(`${this.url}/${conversationId}/messages`, { params });
  }

  translateMessage(conversationId, messageId, targetLanguage) {
    return axios.post(
      `${this.url}/${conversationId}/messages/${messageId}/translate`,
      {
        target_language: targetLanguage,
      }
    );
  }

  react(conversationId, messageId, emoji) {
    return axios.post(
      `${this.url}/${conversationId}/messages/${messageId}/reaction`,
      { emoji }
    );
  }

  edit(conversationId, messageId, content) {
    return axios.post(
      `${this.url}/${conversationId}/messages/${messageId}/edit`,
      { content }
    );
  }
}

export default new MessageApi();
