/* global axios */
import ApiClient from './ApiClient';

class HomeAPI extends ApiClient {
  constructor() {
    super('home', { accountScoped: true, apiVersion: 'v2' });
  }

  // The top of the page: it ignores the filters.
  get() {
    return axios.get(this.url);
  }

  // One section of the indicator cards (leads, appointments, follow_up,
  // outcomes, funnel, ai), for the picked period and filters.
  section({ name, since, until, origem, inboxIds }) {
    return axios.get(`${this.url}/section`, {
      params: {
        name,
        ...HomeAPI.filterParams({ since, until, origem, inboxIds }),
      },
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
