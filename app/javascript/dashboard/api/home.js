/* global axios */
import ApiClient from './ApiClient';

class HomeAPI extends ApiClient {
  constructor() {
    super('home', { accountScoped: true, apiVersion: 'v2' });
  }

  get({ since, until, origem, inboxIds }) {
    return axios.get(this.url, {
      params: HomeAPI.filterParams({ since, until, origem, inboxIds }),
    });
  }

  // The conversations behind one card, a page at a time.
  drilldown({ metric, page, since, until, origem, inboxIds }) {
    return axios.get(`${this.url}/drilldown`, {
      params: {
        metric,
        page,
        ...HomeAPI.filterParams({ since, until, origem, inboxIds }),
      },
    });
  }

  static filterParams({ since, until, origem, inboxIds }) {
    return {
      since,
      until,
      origem: origem || undefined,
      inbox_ids: inboxIds?.length ? inboxIds : undefined,
    };
  }
}

export default new HomeAPI();
