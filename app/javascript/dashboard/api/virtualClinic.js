/* global axios */
import ApiClient from './ApiClient';

class VirtualClinicAPI extends ApiClient {
  constructor() {
    super('virtual_clinic', { accountScoped: true, apiVersion: 'v2' });
  }

  // `{ ai_team: { visible, enabled, missing, members } }`
  getConfig() {
    const request = axios.get(`${this.url}/config`);
    this.assetsVersion = request.then(({ data }) => data.assets_version);
    return request;
  }

  // One PNG of the clinic art (served only to logged-in users). The art
  // version goes in the URL: browsers keep the art cached until new art is
  // uploaded.
  async getAsset(path) {
    if (!this.assetsVersion) this.getConfig();
    const { data } = await axios.get(`${this.url}/assets/${path}`, {
      params: { v: await this.assetsVersion },
      responseType: 'blob',
    });
    return data;
  }

  // `{ secretary: { active_conversations, in_follow_up },
  //    manager: { month: { leads, appointments, conversion_rate } } }`
  getStatus() {
    return axios.get(`${this.url}/status`);
  }

  // `{ persona, thread_id, messages }`
  getThread(persona) {
    return axios.get(`${this.url}/threads/${persona}`);
  }

  // `{ messages: [question, pendingAnswer] }`; 429 over the daily limit.
  sendMessage(persona, content) {
    return axios.post(`${this.url}/threads/${persona}/messages`, { content });
  }

  resetThread(persona) {
    return axios.post(`${this.url}/threads/${persona}/reset`);
  }

  // `{ layout, updated_at, updated_by }`; `layout` is null for the default.
  getLayout() {
    return axios.get(`${this.url}/layout`);
  }

  saveLayout(layout) {
    return axios.put(`${this.url}/layout`, { layout });
  }

  resetLayout() {
    return axios.delete(`${this.url}/layout`);
  }

  // `{ alerts, counts }`: what the AI team raised its hand for.
  getAlerts() {
    return axios.get(`${this.url}/alerts`);
  }

  acknowledgeAlerts(persona) {
    return axios.post(`${this.url}/alerts/acknowledge`, { persona });
  }

  // `{ paths }`: every file of the pack the editor can use.
  // The summaries the user wants from Helena or Luciano (`persona`):
  // `{ daily, weekly, monthly, hour }`.
  getSummary(persona) {
    return axios.get(`${this.url}/summary`, { params: { persona } });
  }

  saveSummary(persona, summary) {
    return axios.put(`${this.url}/summary`, { ...summary, persona });
  }

  listAssets() {
    return axios.get(`${this.url}/assets`);
  }

  updateSettings(settings) {
    return axios.patch(`${this.url}/settings`, settings);
  }
}

export default new VirtualClinicAPI();
