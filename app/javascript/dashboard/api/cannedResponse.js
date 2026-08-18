/* global axios */

import ApiClient from './ApiClient';

class CannedResponse extends ApiClient {
  constructor() {
    super('canned_responses', { accountScoped: true });
  }

  // `inboxId` narrows the list to the global responses plus that inbox's,
  // which is what the composer needs inside a conversation. Omitting it lists
  // everything, as the settings screen does.
  get({ searchKey, inboxId } = {}) {
    return axios.get(this.url, {
      params: {
        search: searchKey || undefined,
        inbox_id: inboxId || undefined,
      },
    });
  }
}

export default new CannedResponse();
