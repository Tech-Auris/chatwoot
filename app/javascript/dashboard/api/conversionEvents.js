import ApiClient from './ApiClient';

class ConversionEventsAPI extends ApiClient {
  constructor() {
    super('conversion_events', { accountScoped: true });
  }
}

export default new ConversionEventsAPI();
