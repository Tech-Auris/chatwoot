import FunnelStagesAPI from '../../api/funnelStages';
import types from '../mutation-types';

// Funnel stages are read in two places — the badge on the conversation header
// and the conversation filter — and they change rarely, so they are fetched
// once and kept here instead of on every conversation opened.
export const state = {
  records: [],
  uiFlags: { isFetching: false, isFetched: false },
};

export const getters = {
  getFunnelStages: $state => $state.records,
  getUIFlags: $state => $state.uiFlags,
};

export const actions = {
  get: async ({ commit, state: $state }) => {
    if ($state.uiFlags.isFetched || $state.uiFlags.isFetching) return;

    commit(types.SET_FUNNEL_STAGES_UI_FLAG, { isFetching: true });
    try {
      const { data } = await FunnelStagesAPI.active();
      commit(
        types.SET_FUNNEL_STAGES,
        (data?.payload || []).filter(stage => stage.active)
      );
      commit(types.SET_FUNNEL_STAGES_UI_FLAG, {
        isFetching: false,
        isFetched: true,
      });
    } catch (error) {
      // An account without the funnel enabled answers 403 here; leaving the
      // list empty simply hides the badge and the filter option.
      commit(types.SET_FUNNEL_STAGES_UI_FLAG, {
        isFetching: false,
        isFetched: true,
      });
    }
  },
};

export const mutations = {
  [types.SET_FUNNEL_STAGES]($state, records) {
    $state.records = records;
  },
  [types.SET_FUNNEL_STAGES_UI_FLAG]($state, uiFlags) {
    $state.uiFlags = { ...$state.uiFlags, ...uiFlags };
  },
};

export default { namespaced: true, state, getters, actions, mutations };
