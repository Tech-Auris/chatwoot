/* global axios */

const URL = '/api/v1/oauth/authorization';

export default {
  show(params) {
    return axios.get(URL, { params });
  },
  create(params) {
    return axios.post(URL, params);
  },
};
