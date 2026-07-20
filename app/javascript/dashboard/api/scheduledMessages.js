/* global axios */
import ApiClient from './ApiClient';

class ScheduledMessagesApi extends ApiClient {
  constructor() {
    super('scheduled_messages', { accountScoped: true });
  }

  getForDay(params) {
    return axios.get(this.url, { params });
  }

  getForRange(params) {
    return axios.get(this.url, { params });
  }
}

export default new ScheduledMessagesApi();
