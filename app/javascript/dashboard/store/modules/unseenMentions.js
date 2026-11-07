import MentionsAPI from '../../api/mentions';

export const state = {
  records: {},
};

export const getters = {
  getCount($state) {
    return Object.keys($state.records).length;
  },
  getByConversation: $state => conversationId => {
    return $state.records[String(conversationId)] || null;
  },
};

export const actions = {
  async get({ commit }) {
    try {
      const { data } = await MentionsAPI.getUnseen();
      commit('SET_UNSEEN_MENTIONS', data.payload);
    } catch (error) {
      // Keep the current badge when the request fails.
    }
  },
  markSeen({ commit }, conversationId) {
    commit('REMOVE_UNSEEN_MENTION', conversationId);
  },
};

export const mutations = {
  SET_UNSEEN_MENTIONS($state, mentions = []) {
    $state.records = mentions.reduce((records, mention) => {
      records[String(mention.conversation_id)] = {
        mentionedAt: mention.mentioned_at,
        mentionedBy: mention.mentioned_by,
      };
      return records;
    }, {});
  },
  REMOVE_UNSEEN_MENTION($state, conversationId) {
    const { [String(conversationId)]: _removed, ...rest } = $state.records;
    $state.records = rest;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
