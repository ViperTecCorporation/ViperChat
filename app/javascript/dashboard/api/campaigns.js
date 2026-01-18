/* global axios */
import ApiClient from './ApiClient';

const buildCampaignFormData = campaign => {
  const formData = new FormData();
  Object.entries(campaign).forEach(([key, value]) => {
    if (value === undefined || value === null) return;
    if (key === 'mediaFile') {
      formData.append('campaign[media]', value);
      return;
    }
    if (['audience', 'template_params', 'trigger_rules'].includes(key)) {
      formData.append(`campaign[${key}]`, JSON.stringify(value));
      return;
    }
    formData.append(`campaign[${key}]`, value);
  });
  return formData;
};

class CampaignsAPI extends ApiClient {
  constructor() {
    super('campaigns', { accountScoped: true });
  }

  create(data) {
    if (data?.mediaFile) {
      const payload = buildCampaignFormData(data);
      return axios.post(this.url, payload, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
    }
    return axios.post(this.url, data);
  }

  duplicate(id) {
    return axios.post(`${this.url}/${id}/duplicate`);
  }
}

export default new CampaignsAPI();
