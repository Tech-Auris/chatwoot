import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import MarketingIntegrationsAPI from '../../api/marketingIntegrations';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export const getters = {
  getMarketingIntegrations(_state) {
    return _state.records;
  },
  getMarketingIntegrationByProvider: _state => provider => {
    return _state.records.find(record => record.provider === provider) || null;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  get: async ({ commit }) => {
    commit(types.SET_MARKETING_INTEGRATIONS_UI_FLAG, { isFetching: true });
    try {
      const response = await MarketingIntegrationsAPI.get();
      commit(types.SET_MARKETING_INTEGRATIONS, response.data.payload);
    } finally {
      commit(types.SET_MARKETING_INTEGRATIONS_UI_FLAG, { isFetching: false });
    }
  },

  create: async ({ commit }, params) => {
    commit(types.SET_MARKETING_INTEGRATIONS_UI_FLAG, { isCreating: true });
    try {
      const response = await MarketingIntegrationsAPI.create(params);
      commit(types.ADD_MARKETING_INTEGRATION, response.data);
      return response.data;
    } catch (error) {
      throw new Error(
        error?.response?.data?.message || 'Could not save integration'
      );
    } finally {
      commit(types.SET_MARKETING_INTEGRATIONS_UI_FLAG, { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...params }) => {
    commit(types.SET_MARKETING_INTEGRATIONS_UI_FLAG, { isUpdating: true });
    try {
      const response = await MarketingIntegrationsAPI.update(id, params);
      commit(types.EDIT_MARKETING_INTEGRATION, response.data);
      return response.data;
    } catch (error) {
      throw new Error(
        error?.response?.data?.message || 'Could not save integration'
      );
    } finally {
      commit(types.SET_MARKETING_INTEGRATIONS_UI_FLAG, { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit(types.SET_MARKETING_INTEGRATIONS_UI_FLAG, { isDeleting: true });
    try {
      await MarketingIntegrationsAPI.delete(id);
      commit(types.DELETE_MARKETING_INTEGRATION, id);
    } finally {
      commit(types.SET_MARKETING_INTEGRATIONS_UI_FLAG, { isDeleting: false });
    }
  },
};

export const mutations = {
  [types.SET_MARKETING_INTEGRATIONS_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  [types.SET_MARKETING_INTEGRATIONS]: MutationHelpers.set,
  [types.ADD_MARKETING_INTEGRATION]: MutationHelpers.create,
  [types.EDIT_MARKETING_INTEGRATION]: MutationHelpers.update,
  [types.DELETE_MARKETING_INTEGRATION]: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
