import api from 'dashboard/api/messageFavorites';

const pending = new Map();
const keyFor = (getters, conversationId) =>
  `${getters.getCurrentUser?.id}:${getters.getCurrentAccountId}:${conversationId}`;

export default {
  namespaced: true,
  state: () => ({ conversations: {}, loaded: {} }),
  getters: {
    isFavorite:
      (state, getters, rootState, rootGetters) => (conversationId, messageId) =>
        (
          state.conversations[keyFor(rootGetters, conversationId)] || []
        ).includes(Number(messageId)),
  },
  mutations: {
    set(state, { key, ids }) {
      state.conversations[key] = ids;
      state.loaded[key] = true;
    },
    update(state, { key, id, favorite }) {
      const ids = (state.conversations[key] || []).filter(
        value => value !== Number(id)
      );
      state.conversations[key] = favorite ? [...ids, Number(id)] : ids;
    },
  },
  actions: {
    load({ state, commit, rootGetters }, conversationId) {
      const key = keyFor(rootGetters, conversationId);
      if (state.loaded[key]) return Promise.resolve();
      if (pending.has(key)) return pending.get(key);
      const request = api
        .list({ conversation_id: conversationId, ids_only: true })
        .then(({ data }) => commit('set', { key, ids: data.ids }))
        .finally(() => pending.delete(key));
      pending.set(key, request);
      return request;
    },
    async setFavorite(
      { commit, rootGetters },
      { conversationId, messageId, favorite }
    ) {
      const key = keyFor(rootGetters, conversationId);
      if (favorite) await api.favorite(messageId);
      else await api.unfavorite(messageId);
      commit('update', { key, id: messageId, favorite });
    },
  },
};
