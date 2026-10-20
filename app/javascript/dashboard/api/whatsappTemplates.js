/* global axios */
import ApiClient from './ApiClient';

class WhatsappTemplatesAPI extends ApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  get(inboxId) {
    return axios.get(`${this.url}/${inboxId}/whatsapp_templates`);
  }

  create(inboxId, template) {
    return axios.post(`${this.url}/${inboxId}/whatsapp_templates`, {
      template,
    });
  }

  sync(inboxId) {
    return axios.post(`${this.url}/${inboxId}/whatsapp_templates/sync`);
  }
}

export default new WhatsappTemplatesAPI();
