import axios from 'axios';
import ApiClient from './ApiClient';

class CampaignsAPI extends ApiClient {
  constructor() {
    super('campaigns', { accountScoped: true });
  }

  // Turns a CSV of contacts into the audience of a campaign about to be
  // created. Answers with the contact ids plus what the file produced, so the
  // form can show it before the campaign exists.
  importAudience(file) {
    const formData = new FormData();
    formData.append('file', file);

    return axios.post(`${this.url}/import_audience`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }
}

export default new CampaignsAPI();
