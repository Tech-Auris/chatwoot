/* global axios */
import ApiClient from './ApiClient';

class AppointmentReportsAPI extends ApiClient {
  constructor() {
    super('appointment_reports', { accountScoped: true, apiVersion: 'v2' });
  }

  fetch({ from, to, professional, erpSourceId, page }) {
    return axios.get(this.url, {
      params: {
        from,
        to,
        professional: professional || undefined,
        erp_source_id: erpSourceId || undefined,
        page,
      },
    });
  }
}

export default new AppointmentReportsAPI();
