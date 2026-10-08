import LossReasonAPI from '../../api/lossReason';
import types from '../mutation-types';

// Loss reasons are global and change rarely (Super Admin), so rules and forms
// that offer them fetch the list once and keep it here.
export const state = {
  records: [],
  uiFlags: { isFetching: false, isFetched: false },
};

export const getters = {
  getLossReasons: $state => $state.records,
};

export const actions = {
  get: async ({ commit, state: $state }) => {
    if ($state.uiFlags.isFetched || $state.uiFlags.isFetching) return;

    commit(types.SET_LOSS_REASONS_UI_FLAG, { isFetching: true });
    try {
      const { data } = await LossReasonAPI.get();
      commit(
        types.SET_LOSS_REASONS,
        (data?.payload || []).filter(reason => reason.active)
      );
    } finally {
      commit(types.SET_LOSS_REASONS_UI_FLAG, {
        isFetching: false,
        isFetched: true,
      });
    }
  },
};

export const mutations = {
  [types.SET_LOSS_REASONS]($state, records) {
    $state.records = records;
  },
  [types.SET_LOSS_REASONS_UI_FLAG]($state, uiFlags) {
    $state.uiFlags = { ...$state.uiFlags, ...uiFlags };
  },
};

export default { namespaced: true, state, getters, actions, mutations };
