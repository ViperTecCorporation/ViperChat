/* global axios */

import ApiClient from './ApiClient';

class NotificationSubscriptions extends ApiClient {
  constructor() {
    super('notification_subscriptions');
  }

  destroy(pushToken) {
    return axios.delete(this.url, { params: { push_token: pushToken } });
  }
}

export default new NotificationSubscriptions();
