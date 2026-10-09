/* global axios */
import ApiClient from './ApiClient';

class FollowUpReportsAPI extends ApiClient {
  constructor() {
    super('follow_up_reports', {
      accountScoped: true,
      apiVersion: 'v2',
    });
  }

  fetch(filters) {
    return axios.get(this.url, { params: this.params(filters) });
  }

  exportCsv(filters) {
    return axios.get(`${this.url}.csv`, { params: this.params(filters) });
  }

  // eslint-disable-next-line class-methods-use-this
  params({
    from,
    to,
    inboxId,
    hourFrom,
    hourTo,
    q,
    deliveryStatus,
    outcome,
    page,
  }) {
    return {
      from,
      to,
      inbox_id: inboxId || undefined,
      hour_from: hourFrom === '' ? undefined : hourFrom,
      hour_to: hourTo === '' ? undefined : hourTo,
      q: q || undefined,
      delivery_status: deliveryStatus || undefined,
      outcome: outcome || undefined,
      page,
    };
  }
}

export default new FollowUpReportsAPI();
