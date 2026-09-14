/* global axios */
import ApiClient from './ApiClient';

class MessageFavorites extends ApiClient {
  constructor() {
    super('message_favorites', { accountScoped: true });
  }

  list(params) {
    return axios.get(this.url, { params });
  }

  favorite(messageId) {
    return axios.post(this.url, { message_id: messageId });
  }

  unfavorite(messageId) {
    return axios.delete(`${this.url}/${messageId}`);
  }
}

export default new MessageFavorites();
