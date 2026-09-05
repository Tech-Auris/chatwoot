/* global axios */
import ApiClient from './ApiClient';

// Signs an update-campaign acceptance from the dashboard. The public
// sales-checkout flow signs by a different (unauthenticated) path — this
// client only serves managers signing from inside the operator panel.
class TermsAcceptancesApi extends ApiClient {
  constructor() {
    super('terms_acceptances', { accountScoped: true });
  }

  sign(token) {
    return axios.post(`${this.url}/${token}/sign`);
  }
}

export default new TermsAcceptancesApi();
