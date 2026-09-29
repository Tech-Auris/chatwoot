/* global axios */
import ApiClient from './ApiClient';

class SummaryReportsAPI extends ApiClient {
  constructor() {
    super('summary_reports', { accountScoped: true, apiVersion: 'v2' });
  }

  getTeamReports({ since, until, businessHours } = {}) {
    return axios.get(`${this.url}/team`, {
      params: {
        since,
        until,
        business_hours: businessHours,
      },
    });
  }

  getAgentReports({ since, until, businessHours } = {}) {
    return axios.get(`${this.url}/agent`, {
      params: {
        since,
        until,
        business_hours: businessHours,
      },
    });
  }

  getInboxReports({ since, until, businessHours } = {}) {
    return axios.get(`${this.url}/inbox`, {
      params: {
        since,
        until,
        business_hours: businessHours,
      },
    });
  }

  getLabelReports({ since, until, businessHours } = {}) {
    return axios.get(`${this.url}/label`, {
      params: {
        since,
        until,
        business_hours: businessHours,
      },
    });
  }

  getOrigemReports({ since, until, businessHours } = {}) {
    return axios.get(`${this.url}/origem`, {
      params: {
        since,
        until,
        business_hours: businessHours,
      },
    });
  }

  getCampaignAnalytics({ since, until: untilTs } = {}) {
    return axios.get(`${this.url}/campaign_analytics`, {
      params: {
        since,
        until: untilTs,
      },
    });
  }

  getFunnelReports({ since, until: untilTs, inboxId, label, origem } = {}) {
    return axios.get(`${this.url}/funnel`, {
      params: {
        since,
        until: untilTs,
        inbox_id: inboxId,
        label,
        origem,
      },
    });
  }

  getFunnelConversionReports({
    since,
    until: untilTs,
    inboxId,
    label,
    origem,
  } = {}) {
    return axios.get(`${this.url}/funnel_conversion`, {
      params: {
        since,
        until: untilTs,
        inbox_id: inboxId,
        label,
        origem,
      },
    });
  }

  // Conversations behind one number of the conversion report: a chart stage
  // (`stageKey`), the losses (`kind: 'loss'`, optionally one reason) or one
  // ad's leads (`kind: 'ad'` + `sourceId`).
  getFunnelConversionDrilldown({
    since,
    until: untilTs,
    inboxId,
    label,
    origem,
    stageKey,
    kind,
    lossReasonId,
    sourceId,
    metric,
    page,
  } = {}) {
    return axios.get(`${this.url}/funnel_conversion_drilldown`, {
      params: {
        since,
        until: untilTs,
        inbox_id: inboxId,
        label,
        origem,
        stage_key: stageKey,
        kind,
        loss_reason_id: lossReasonId,
        source_id: sourceId,
        metric,
        page,
      },
    });
  }
}

export default new SummaryReportsAPI();
