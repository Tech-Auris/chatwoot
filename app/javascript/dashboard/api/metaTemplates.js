/* global axios */
import ApiClient from './ApiClient';

class MetaTemplatesAPI extends ApiClient {
  constructor() {
    super('meta_templates', { accountScoped: true, apiVersion: 'v2' });
  }

  // Fetches the cached templates for a given Cloud WhatsApp inbox.
  // Backend returns `{ inbox, templates, last_synced_at }`.
  fetch({ inboxId }) {
    return axios.get(this.url, { params: { inbox_id: inboxId } });
  }

  // Triggers an inline sync with Meta and returns the fresh payload.
  // Same shape as `fetch`.
  sync({ inboxId }) {
    return axios.post(
      `${this.url}/sync`,
      {},
      { params: { inbox_id: inboxId } }
    );
  }

  // Submits a new template for Meta approval. `template` matches Meta's
  // `/message_templates` shape ({ name, language, category, components })
  // so future slices that compose header/footer/buttons don't need a
  // translation layer.
  create({ inboxId, template }) {
    return axios.post(
      this.url,
      { template },
      { params: { inbox_id: inboxId } }
    );
  }

  // Deletes the template on Meta. Backend resolves `id` → template name
  // from the cached list, so callers just pass the Meta template id.
  // Returns the refreshed { templates, last_synced_at } payload so the
  // list can update without a second GET.
  delete({ inboxId, templateId }) {
    return axios.delete(`${this.url}/${templateId}`, {
      params: { inbox_id: inboxId },
    });
  }

  // Updates a template on Meta. Backend only forwards category +
  // components (name/language are immutable), but the form still sends
  // the full template shape so a single component covers create and
  // edit — the backend slice does the right thing.
  update({ inboxId, templateId, template }) {
    return axios.patch(
      `${this.url}/${templateId}`,
      { template },
      { params: { inbox_id: inboxId } }
    );
  }

  // Per-template send funnel over a rolling window (7d / 30d / 90d).
  // Backend returns { period, period_days, funnel: { sent, accepted_by_meta,
  // failed_sync, delivered, read, failed_after_accept } }.
  analytics({ inboxId, templateId, period }) {
    return axios.get(`${this.url}/${templateId}/analytics`, {
      params: { inbox_id: inboxId, period },
    });
  }

  // Uploads a header image through our backend, which proxies the file
  // to Meta's resumable upload endpoint and returns the `header_handle`
  // Meta requires in the template payload. Sent as multipart because we
  // forward the raw file bytes.
  uploadHeaderMedia({ inboxId, file }) {
    const form = new FormData();
    form.append('file', file);
    return axios.post(`${this.url}/upload_header_media`, form, {
      params: { inbox_id: inboxId },
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }
}

export default new MetaTemplatesAPI();
