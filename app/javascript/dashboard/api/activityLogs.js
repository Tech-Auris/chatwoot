/* global axios */
import ApiClient from './ApiClient';

class ActivityLogsAPI extends ApiClient {
  constructor() {
    super('activity_logs', { accountScoped: true });
  }

  // `params`: page, since, until, user_id, auditable_type, log_action, source, q.
  get(params) {
    return axios.get(this.url, { params });
  }

  // The log with its changes and the `history` of the same record.
  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  // Same filters as `get`; the backend answers with the CSV text.
  export(params) {
    return axios.get(`${this.url}/export`, { params, responseType: 'text' });
  }
}

export default new ActivityLogsAPI();
