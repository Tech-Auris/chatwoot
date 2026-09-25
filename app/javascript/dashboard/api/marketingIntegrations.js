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
}

export default new MarketingIntegrationsAPI();
