/* global axios */
import ApiClient from './ApiClient';

class ConversationApi extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  getLabels(conversationID) {
    return axios.get(`${this.url}/${conversationID}/labels`);
  }

  getLinks(conversationID, page = 1) {
    return axios.get(`${this.url}/${conversationID}/links`, {
      params: { page },
    });
  }

  setArchived(conversationID, archived) {
    return axios.post(`${this.url}/${conversationID}/archive`, { archived });
  }

  getArchived(page = 1) {
    return axios.get(`${this.url}/archived`, { params: { page } });
  }

  getArchiveState() {
    return axios.get(`${this.url}/archived`, { params: { ids_only: true } });
  }

  updateLabels(conversationID, labels) {
    return axios.post(`${this.url}/${conversationID}/labels`, { labels });
  }

  forwardMessages(conversationID, payload) {
    return axios.post(`${this.url}/${conversationID}/forwards`, payload);
  }

  getUnreadCounts() {
    return axios.get(`${this.url}/unread_counts`);
  }

  setPinned(conversationID, pinned) {
    return axios.post(`${this.url}/${conversationID}/pin`, { pinned });
  }
}

export default new ConversationApi();
