import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import ConversionEventsAPI from '../../api/conversionEvents';

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
  getConversionEvents(_state) {
    return _state.records;
  },
  getConversionEventById: _state => id => {
    return _state.records.find(record => record.id === Number(id)) || null;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  get: async ({ commit }) => {
    commit(types.SET_CONVERSION_EVENTS_UI_FLAG, { isFetching: true });
    try {
      const response = await ConversionEventsAPI.get();
      commit(types.SET_CONVERSION_EVENTS, response.data.payload);
    } finally {
      commit(types.SET_CONVERSION_EVENTS_UI_FLAG, { isFetching: false });
    }
  },

  create: async ({ commit }, params) => {
    commit(types.SET_CONVERSION_EVENTS_UI_FLAG, { isCreating: true });
    try {
      const response = await ConversionEventsAPI.create(params);
      commit(types.ADD_CONVERSION_EVENT, response.data);
      return response.data;
    } catch (error) {
      throw new Error(error?.response?.data?.message || 'Could not save event');
    } finally {
      commit(types.SET_CONVERSION_EVENTS_UI_FLAG, { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...params }) => {
    commit(types.SET_CONVERSION_EVENTS_UI_FLAG, { isUpdating: true });
    try {
      const response = await ConversionEventsAPI.update(id, params);
      commit(types.EDIT_CONVERSION_EVENT, response.data);
      return response.data;
    } catch (error) {
      throw new Error(error?.response?.data?.message || 'Could not save event');
    } finally {
      commit(types.SET_CONVERSION_EVENTS_UI_FLAG, { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit(types.SET_CONVERSION_EVENTS_UI_FLAG, { isDeleting: true });
    try {
      await ConversionEventsAPI.delete(id);
      commit(types.DELETE_CONVERSION_EVENT, id);
    } finally {
      commit(types.SET_CONVERSION_EVENTS_UI_FLAG, { isDeleting: false });
    }
  },
};

export const mutations = {
  [types.SET_CONVERSION_EVENTS_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  [types.SET_CONVERSION_EVENTS]: MutationHelpers.set,
  [types.ADD_CONVERSION_EVENT]: MutationHelpers.create,
  [types.EDIT_CONVERSION_EVENT]: MutationHelpers.update,
  [types.DELETE_CONVERSION_EVENT]: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
