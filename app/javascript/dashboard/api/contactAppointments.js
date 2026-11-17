/* global axios */
import ApiClient from './ApiClient';

class ContactAppointments extends ApiClient {
  constructor() {
    super('contacts', { accountScoped: true });
  }

  get(contactId) {
    return axios.get(`${this.url}/${contactId}/appointments`);
  }
}

export default new ContactAppointments();
