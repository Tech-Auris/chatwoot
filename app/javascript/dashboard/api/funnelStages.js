/* global axios */
import ApiClient from './ApiClient';

class FunnelStagesAPI extends ApiClient {
  constructor() {
    super('funnel_stages', { accountScoped: true });
  }

  // Only the stages an operator can actually move a conversation into.
  active() {
    return axios.get(this.url);
  }
}

export default new FunnelStagesAPI();
