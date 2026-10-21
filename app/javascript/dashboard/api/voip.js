/* global axios */
export class VoipAPI {
  constructor(accountId) {
    if (!/^\d+$/.test(String(accountId))) throw new Error('invalid_account');
    this.url = `/api/v1/accounts/${accountId}/voip`;
    this.accountId = Number(accountId);
  }

  profile(accountUserId) {
    return axios.get(`${this.url}/profile`, {
      params: { account_user_id: accountUserId },
    });
  }

  saveBinding(serviceId, binding, accountUserId) {
    return axios.patch(`${this.url}/profile`, {
      service_id: serviceId,
      binding,
      account_user_id: accountUserId,
    });
  }

  activate(bindingId, accountUserId) {
    return axios.post(`${this.url}/profile/activate`, {
      binding_id: bindingId,
      account_user_id: accountUserId,
    });
  }

  bootstrap(bindingId) {
    return axios.post(`${this.url}/registration`, { binding_id: bindingId });
  }

  services() {
    return axios.get(`${this.url}/services`);
  }

  agents() {
    return axios.get(`${this.url}/services/agents`);
  }

  saveService(id, service) {
    return id
      ? axios.patch(`${this.url}/services/${id}`, { service })
      : axios.post(`${this.url}/services`, { service });
  }

  disableService(id) {
    return axios.delete(`${this.url}/services/${id}`);
  }

  calls(params) {
    return axios.get(`${this.url}/calls`, { params });
  }

  call(id) {
    return axios.get(`${this.url}/calls/${id}`);
  }

  directory(params) {
    return axios.get(`${this.url}/directory`, { params });
  }

  identity(params) {
    return axios.get(`${this.url}/identity`, { params });
  }

  createCall(bindingId, call) {
    return axios.post(`${this.url}/calls`, { binding_id: bindingId, call });
  }

  observe(id, observation) {
    return axios.post(`${this.url}/calls/${id}/observe`, { observation });
  }

  favorites() {
    return axios.get(`${this.url}/favorites`);
  }

  favorite(serviceId, favorite) {
    return axios.post(`${this.url}/favorites`, {
      service_id: serviceId,
      favorite,
    });
  }

  removeFavorite(id) {
    return axios.delete(`${this.url}/favorites/${id}`);
  }
}
