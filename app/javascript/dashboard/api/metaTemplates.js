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
}

export default new MetaTemplatesAPI();
