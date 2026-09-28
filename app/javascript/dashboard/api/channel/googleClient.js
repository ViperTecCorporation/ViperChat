/* global axios */
import ApiClient from '../ApiClient';

class MicrosoftClient extends ApiClient {
  constructor() {
    super('google', { accountScoped: true });
  }

  generateAuthorization(payload) {
    return axios.post(`${this.url}/authorization`, payload);
  }

  getHistory(inboxId) {
    return axios.get(`${this.url}/email_history`, {
      params: { inbox_id: inboxId },
    });
  }

  startHistory(inboxId, period) {
    return axios.post(`${this.url}/email_history`, {
      inbox_id: inboxId,
      period,
    });
  }

  stopHistory(inboxId) {
    return axios.delete(`${this.url}/email_history`, {
      params: { inbox_id: inboxId },
    });
  }
}

export default new MicrosoftClient();
