import VirtualClinicAPI from 'dashboard/api/virtualClinic';

// Open alerts of the Clínica virtual AI team, per teammate: the "❗" on the
// map and, with the internal chat unread count, the menu badge.
export const state = { alertCounts: {} };

export const getters = {
  getAlertCounts: $state => $state.alertCounts,
  getMenuBadge: ($state, _getters, _rootState, rootGetters) =>
    (rootGetters['internalChat/getUnreadCount'] || 0) +
    Object.values($state.alertCounts).reduce((sum, count) => sum + count, 0),
};

export const actions = {
  async fetchAlertCounts({ commit }) {
    const { data } = await VirtualClinicAPI.getAlerts();
    commit('SET_ALERT_COUNTS', data.counts);
  },
  setAlertCounts({ commit }, counts) {
    commit('SET_ALERT_COUNTS', counts);
  },
};

export const mutations = {
  SET_ALERT_COUNTS($state, counts) {
    $state.alertCounts = counts || {};
  },
};

export default { namespaced: true, state, getters, actions, mutations };
