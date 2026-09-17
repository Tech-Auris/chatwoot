import ApiClient from './ApiClient';

class MarketingIntegrationsAPI extends ApiClient {
  constructor() {
    super('marketing_integrations', { accountScoped: true });
  }
}

export default new MarketingIntegrationsAPI();
