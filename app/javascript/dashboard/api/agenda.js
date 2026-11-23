/* global axios */
import ApiClient from './ApiClient';

class AgendaAPI extends ApiClient {
  constructor() {
    super('agenda', { accountScoped: true });
  }

  // `from` and `to` as yyyy-MM-dd, both included, up to 7 days.
  fetch({ from, to }) {
    return axios.get(this.url, { params: { from, to } });
  }
}

export default new AgendaAPI();
