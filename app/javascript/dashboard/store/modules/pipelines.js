import PipelinesAPI from '../../api/pipelines';
import types from '../mutation-types';

// The clinic pipelines (with their stages), shared by the pipeline selector,
// "Adicionar a" and the "Funis" button of the conversation header. Fetched
// once; anything that changes a pipeline calls `get` with `force`.
export const state = {
  records: [],
  uiFlags: { isFetching: false, isFetched: false },
};

export const getters = {
  getPipelines: $state => $state.records,
  getPipeline: $state => id => $state.records.find(record => record.id === id),
  getUIFlags: $state => $state.uiFlags,
};

export const actions = {
  get: async ({ commit, state: $state }, { force = false } = {}) => {
    if (!force && ($state.uiFlags.isFetched || $state.uiFlags.isFetching))
      return;

    commit(types.SET_PIPELINES_UI_FLAG, { isFetching: true });
    try {
      const { data } = await PipelinesAPI.get();
      commit(types.SET_PIPELINES, data?.payload || []);
    } catch (error) {
      // Accounts without the funnel answer with an error: no pipelines.
      commit(types.SET_PIPELINES, []);
    } finally {
      commit(types.SET_PIPELINES_UI_FLAG, {
        isFetching: false,
        isFetched: true,
      });
    }
  },
};

export const mutations = {
  [types.SET_PIPELINES]($state, records) {
    $state.records = records;
  },
  [types.SET_PIPELINES_UI_FLAG]($state, uiFlags) {
    $state.uiFlags = { ...$state.uiFlags, ...uiFlags };
  },
};

export default { namespaced: true, state, getters, actions, mutations };
