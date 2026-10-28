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

  update(inboxId, { enabled, teamId, hours }) {
    return axios.patch(`${this.url}/${inboxId}/ai_schedule`, {
      enabled,
      team_id: teamId || null,
      hours,
    });
  }
}

export default new InboxAiScheduleAPI();
