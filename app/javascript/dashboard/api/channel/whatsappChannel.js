/* global axios */
import ApiClient from '../ApiClient';

class WhatsappChannel extends ApiClient {
  constructor() {
    super('whatsapp', { accountScoped: true });
  }

  createEmbeddedSignup(params) {
    return axios.post(`${this.baseUrl()}/whatsapp/authorization`, params);
  }

  postEmbeddedSignupAuthorization({ inboxId, ...params }) {
    return axios.post(`${this.baseUrl()}/whatsapp/authorization`, {
      ...params,
      inbox_id: inboxId,
    });
  }

  rotateZapiWebhookToken(inboxId) {
    return axios.post(
      `${this.baseUrl()}/whatsapp/zapi/${inboxId}/rotate_webhook_token`
    );
  }
}

export default new WhatsappChannel();
