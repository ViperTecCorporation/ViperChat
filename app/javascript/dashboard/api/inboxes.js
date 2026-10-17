/* global axios */
import CacheEnabledApiClient from './CacheEnabledApiClient';

class Inboxes extends CacheEnabledApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  // eslint-disable-next-line class-methods-use-this
  get cacheModelName() {
    return 'inbox';
  }

  getCampaigns(inboxId) {
    return axios.get(`${this.url}/${inboxId}/campaigns`);
  }

  getWhatsappLink(inboxId) {
    return axios.get(`${this.url}/${inboxId}/whatsapp_link`);
  }

  previewWhatsappLink(inboxId, payload) {
    return axios.post(`${this.url}/${inboxId}/whatsapp_link/preview`, payload);
  }

  updateWhatsappLink(inboxId, payload) {
    return axios.put(`${this.url}/${inboxId}/whatsapp_link`, payload);
  }

  deleteWhatsappLink(inboxId) {
    return axios.delete(`${this.url}/${inboxId}/whatsapp_link`);
  }

  getWhatsappLinkReviews(inboxId, params) {
    return axios.get(`${this.url}/${inboxId}/whatsapp_link/reviews`, {
      params,
    });
  }

  recheckWhatsappLinkReview(inboxId, reviewId, version) {
    return axios.post(
      `${this.url}/${inboxId}/whatsapp_link/reviews/${encodeURIComponent(reviewId)}/recheck`,
      { version }
    );
  }

  acknowledgeWhatsappLinkReview(inboxId, reviewId, version) {
    return axios.post(
      `${this.url}/${inboxId}/whatsapp_link/reviews/${encodeURIComponent(reviewId)}/acknowledge`,
      { version }
    );
  }

  deleteInboxAvatar(inboxId) {
    return axios.delete(`${this.url}/${inboxId}/avatar`);
  }

  getAgentBot(inboxId) {
    return axios.get(`${this.url}/${inboxId}/agent_bot`);
  }

  setAgentBot(inboxId, botId) {
    return axios.post(`${this.url}/${inboxId}/set_agent_bot`, {
      agent_bot: botId,
    });
  }

  syncTemplates(inboxId) {
    return axios.post(`${this.url}/${inboxId}/sync_templates`);
  }

  createCSATTemplate(inboxId, template) {
    return axios.post(`${this.url}/${inboxId}/csat_template`, {
      template,
    });
  }

  getCSATTemplateStatus(inboxId) {
    return axios.get(`${this.url}/${inboxId}/csat_template`);
  }

  analyzeCSATTemplateUtility(inboxId, template) {
    return axios.post(`${this.url}/${inboxId}/csat_template/analyze`, {
      template,
    });
  }

  resetSecret(inboxId) {
    return axios.post(`${this.url}/${inboxId}/reset_secret`);
  }

  enableWhatsappCalling(inboxId) {
    return axios.post(`${this.url}/${inboxId}/enable_whatsapp_calling`);
  }

  disableWhatsappCalling(inboxId) {
    return axios.post(`${this.url}/${inboxId}/disable_whatsapp_calling`);
  }

  setInboundCalls(inboxId, enabled) {
    return axios.post(`${this.url}/${inboxId}/set_inbound_calls`, {
      inbound_calls_enabled: enabled,
    });
  }
}

export default new Inboxes();
