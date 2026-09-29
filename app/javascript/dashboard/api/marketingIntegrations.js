/* global axios */
import ApiClient from './ApiClient';

class MarketingIntegrationsAPI extends ApiClient {
  constructor() {
    super('marketing_integrations', { accountScoped: true });
  }

  // Powers the "Nome do evento no Meta" combobox: Standard Events plus
  // the event names the pixel actually received in the last 30 days.
  fetchPixelEvents(id) {
    return axios.get(`${this.url}/${id}/pixel_events`);
  }

  // Ad accounts grid of the Meta integration (spend for the reports).
  getAdAccounts(id) {
    return axios.get(`${this.url}/${id}/ad_accounts`);
  }

  addAdAccount(id, externalId) {
    return axios.post(`${this.url}/${id}/ad_accounts`, {
      external_id: externalId,
    });
  }

  updateAdAccount(id, adAccountId, attributes) {
    return axios.patch(
      `${this.url}/${id}/ad_accounts/${adAccountId}`,
      attributes
    );
  }

  removeAdAccount(id, adAccountId) {
    return axios.delete(`${this.url}/${id}/ad_accounts/${adAccountId}`);
  }

  syncAdAccounts(id) {
    return axios.post(`${this.url}/${id}/ad_accounts/sync`);
  }
}

export default new MarketingIntegrationsAPI();
