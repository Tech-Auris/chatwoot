/* global axios */
import ApiClient from './ApiClient';

// Marketing → Públicos: saved groups of contacts, a rule (dynamic) or a fixed
// list (static).
class AudiencesAPI extends ApiClient {
  constructor() {
    super('audiences', { accountScoped: true });
  }

  list({ kind } = {}) {
    return axios.get(this.url, { params: { kind } });
  }

  // The size of a rule while it is being built.
  preview({ rule, exclusion, window }) {
    return axios.post(`${this.url}/preview`, { rule, exclusion, window });
  }

  contacts(id, page = 1) {
    return axios.get(`${this.url}/${id}/contacts`, { params: { page } });
  }

  // Before a campaign is sent to it: who it reaches and who stays out.
  campaignPreview(id, campaignId) {
    return axios.get(`${this.url}/${id}/campaign_preview`, {
      params: { campaign_id: campaignId },
    });
  }

  // "Baixar lista": the CSV with the chosen columns.
  exportList(id, columns) {
    return axios.post(
      `${this.url}/${id}/export`,
      { columns },
      { responseType: 'blob' }
    );
  }

  snapshot(id, name) {
    return axios.post(`${this.url}/${id}/snapshot`, { name });
  }

  addContacts(id, contactIds) {
    return axios.post(`${this.url}/${id}/add_contacts`, {
      contact_ids: contactIds,
    });
  }

  removeContacts(id, contactIds) {
    return axios.post(`${this.url}/${id}/remove_contacts`, {
      contact_ids: contactIds,
    });
  }

  importFile({ name, file }) {
    const payload = new FormData();
    payload.append('name', name);
    payload.append('file', file);
    return axios.post(`${this.url}/import`, payload);
  }
}

export default new AudiencesAPI();
