/* global axios */
import ApiClient from './ApiClient';

class VirtualClinicAPI extends ApiClient {
  constructor() {
    super('virtual_clinic', { accountScoped: true, apiVersion: 'v2' });
  }

  // `{ ai_team: { visible, enabled, missing, members } }`
  getConfig() {
    return axios.get(`${this.url}/config`);
  }
}

export default new VirtualClinicAPI();
