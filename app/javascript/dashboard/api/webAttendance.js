/* global axios */
import ApiClient from './ApiClient';

class WebAttendanceAPI extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  show(id) {
    return axios.get(`${this.url}/${id}/web_attendance`);
  }

  create(id, data) {
    return axios.post(`${this.url}/${id}/web_attendance`, data);
  }

  revoke(id) {
    return axios.delete(`${this.url}/${id}/web_attendance`);
  }

  seen(id, destination) {
    return axios.post(`${this.url}/${id}/web_attendance/seen`, { destination });
  }

  fallback(id, invitationId) {
    return axios.post(`${this.url}/${id}/web_attendance/fallback`, {
      invitation_id: invitationId,
    });
  }
}

export default new WebAttendanceAPI();
