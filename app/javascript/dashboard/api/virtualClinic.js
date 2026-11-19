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

  updateSettings(settings) {
    return axios.patch(`${this.url}/settings`, settings);
  }
}

export default new VirtualClinicAPI();
