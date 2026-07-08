/* global axios */
import ApiClient from './ApiClient';

class ContactReminders extends ApiClient {
  constructor() {
    super('contact_reminders', { accountScoped: true });
  }

  get(contactId) {
    return axios.get(
      `${this.baseUrl()}/contacts/${contactId}/contact_reminders`
    );
  }

  create(contactId, data) {
    return axios.post(
      `${this.baseUrl()}/contacts/${contactId}/contact_reminders`,
      data
    );
  }

  update(contactId, reminderId, data) {
    return axios.patch(
      `${this.baseUrl()}/contacts/${contactId}/contact_reminders/${reminderId}`,
      data
    );
  }

  delete(contactId, reminderId) {
    return axios.delete(
      `${this.baseUrl()}/contacts/${contactId}/contact_reminders/${reminderId}`
    );
  }
}

export default new ContactReminders();
