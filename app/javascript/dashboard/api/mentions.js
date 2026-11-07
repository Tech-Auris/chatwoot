/* global axios */
import ApiClient from './ApiClient';

class MentionsApi extends ApiClient {
  constructor() {
    super('mentions', { accountScoped: true });
  }

  getUnseen() {
    return axios.get(`${this.url}/unseen`);
  }
}

export default new MentionsApi();
