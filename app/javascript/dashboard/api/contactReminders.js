import ApiClient from './ApiClient';

class ContactReminders extends ApiClient {
  constructor() {
    super('contact_reminders', { accountScoped: true });
  }

  get(contactId) {
    return this.axios.get(
      `${this.urlPrefix}/contacts/${contactId}/contact_reminders`
    );
  }

  create(contactId, data) {
    return this.axios.post(
      `${this.urlPrefix}/contacts/${contactId}/contact_reminders`,
      data
    );
  }

  update(contactId, reminderId, data) {
    return this.axios.patch(
      `${this.urlPrefix}/contacts/${contactId}/contact_reminders/${reminderId}`,
      data
    );
  }

  delete(contactId, reminderId) {
    return this.axios.delete(
      `${this.urlPrefix}/contacts/${contactId}/contact_reminders/${reminderId}`
    );
  }
}

export default new ContactReminders();
