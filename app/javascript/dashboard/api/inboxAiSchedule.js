/* global axios */
import ApiClient from './ApiClient';

// "Horário da IA desligada" of an inbox.
class InboxAiScheduleAPI extends ApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  show(inboxId) {
    return axios.get(`${this.url}/${inboxId}/ai_schedule`);
  }

  update(inboxId, { paused, enabled, teamId, hours }) {
    return axios.patch(`${this.url}/${inboxId}/ai_schedule`, {
      paused,
      enabled,
      team_id: teamId || null,
      hours,
    });
  }
}

export default new InboxAiScheduleAPI();
