/* global axios */
import ApiClient from './ApiClient';

// Clinic pipelines (funis da clínica). The Agendamento stays on `funnel.js`.
class PipelinesAPI extends ApiClient {
  constructor() {
    super('pipelines', { accountScoped: true });
  }

  get({ archived = false } = {}) {
    return axios.get(this.url, { params: archived ? { archived: true } : {} });
  }

  archive(id) {
    return axios.post(`${this.url}/${id}/archive`);
  }

  unarchive(id) {
    return axios.post(`${this.url}/${id}/unarchive`);
  }

  automations(id) {
    return axios.get(`${this.url}/${id}/automations`);
  }

  board(id, params = {}) {
    return axios.get(`${this.url}/${id}/board`, { params });
  }

  stageEntries(id, stageId, page, params = {}) {
    return axios.get(`${this.url}/${id}/stages/${stageId}/entries`, {
      params: { ...params, page },
    });
  }

  createStage(id, stage) {
    return axios.post(`${this.url}/${id}/stages`, stage);
  }

  updateStage(id, stageId, stage) {
    return axios.patch(`${this.url}/${id}/stages/${stageId}`, stage);
  }

  deleteStage(id, stageId, moveToStageId) {
    return axios.delete(`${this.url}/${id}/stages/${stageId}`, {
      params: { move_to_stage_id: moveToStageId },
    });
  }

  reorderStages(id, ids) {
    return axios.post(`${this.url}/${id}/stages/reorder`, { ids });
  }

  addContact(id, contactId) {
    return axios.post(`${this.url}/${id}/entries`, { contact_id: contactId });
  }

  moveEntry(entryId, { stageId, lossReasonId }) {
    return axios.patch(`${this.baseUrl()}/pipeline_entries/${entryId}/move`, {
      pipeline_stage_id: stageId,
      loss_reason_id: lossReasonId,
    });
  }

  removeEntry(entryId) {
    return axios.delete(`${this.baseUrl()}/pipeline_entries/${entryId}`);
  }

  entryEvents(entryId) {
    return axios.get(`${this.baseUrl()}/pipeline_entries/${entryId}/events`);
  }

  contactEntries(contactId) {
    return axios.get(
      `${this.baseUrl()}/contacts/${contactId}/pipeline_entries`
    );
  }
}

export default new PipelinesAPI();
