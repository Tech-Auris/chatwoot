/* global axios */
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

    // The global `axios` is the configured instance that carries the auth
    // headers; the bare npm module does not, and every request 401s.
    return axios.post(`${this.url}/import_audience`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  // Lists who a campaign would reach, for either audience source, before the
  // campaign exists.
  audiencePreview({ labelIds = [], contactIds = [], page = 1 }) {
    return axios.get(`${this.url}/audience_preview`, {
      params: { label_ids: labelIds, contact_ids: contactIds, page },
    });
  }
}

export default new CampaignsAPI();
