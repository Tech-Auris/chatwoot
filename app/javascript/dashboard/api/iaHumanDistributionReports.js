/* global axios */
import ApiClient from './ApiClient';

class IaHumanDistributionReportsAPI extends ApiClient {
  constructor() {
    super('ia_human_distribution_reports', {
      accountScoped: true,
      apiVersion: 'v2',
    });
  }

  fetch({ from, to, inboxId, dateBasis, page }) {
    return axios.get(this.url, {
      params: {
        from,
        to,
        inbox_id: inboxId || undefined,
        date_basis: dateBasis,
        page,
      },
    });
  }
}

export default new IaHumanDistributionReportsAPI();
