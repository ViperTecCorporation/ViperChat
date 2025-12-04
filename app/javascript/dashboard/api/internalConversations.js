/* global axios */
import ApiClient from './ApiClient';

class InternalConversationsAPI extends ApiClient {
  constructor() {
    super('internal_conversations', { accountScoped: true });
  }

  create(payload) {
    return axios.post(this.url, payload);
  }
}

export default new InternalConversationsAPI();

