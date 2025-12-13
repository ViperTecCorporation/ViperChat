import * as types from '../mutation-types';

const state = {
  currentPage: {
    me: 0,
    unassigned: 0,
    all: 0,
    internal: 0,
    appliedFilters: 0,
  },
  hasEndReached: {
    me: false,
    unassigned: false,
    all: false,
    internal: false,
    appliedFilters: false,
  },
};

export const getters = {
  getHasEndReached: $state => filter => {
    return $state.hasEndReached[filter];
  },
  getCurrentPageFilter: $state => filter => {
    return $state.currentPage[filter];
  },
  getCurrentPage: $state => {
    return $state.currentPage;
  },
};

export const actions = {
  setCurrentPage({ commit }, { filter, page }) {
    commit(types.default.SET_CURRENT_PAGE, { filter, page });
  },
  setEndReached({ commit }, { filter }) {
    commit(types.default.SET_CONVERSATION_END_REACHED, { filter });
  },
  reset({ commit }) {
    commit(types.default.CLEAR_CONVERSATION_PAGE);
  },
};

export const mutations = {
  [types.default.SET_CURRENT_PAGE]: ($state, { filter, page }) => {
    const safePage = Number.isFinite(Number(page)) ? Number(page) : 0;
    $state.currentPage = {
      ...$state.currentPage,
      [filter]: safePage,
    };
  },
  [types.default.SET_CONVERSATION_END_REACHED]: ($state, { filter }) => {
    if (filter === 'all') {
      $state.hasEndReached = {
        ...$state.hasEndReached,
        unassigned: true,
        me: true,
      };
    }
    $state.hasEndReached = {
      ...$state.hasEndReached,
      [filter]: true,
    };
  },
  [types.default.CLEAR_CONVERSATION_PAGE]: $state => {
    const hasInternal = Object.prototype.hasOwnProperty.call(
      $state.currentPage,
      'internal'
    );
    $state.currentPage = {
      me: 0,
      unassigned: 0,
      all: 0,
      appliedFilters: 0,
      ...(hasInternal ? { internal: 0 } : {}),
    };

    const hasInternalEndReached = Object.prototype.hasOwnProperty.call(
      $state.hasEndReached,
      'internal'
    );
    $state.hasEndReached = {
      me: false,
      unassigned: false,
      all: false,
      appliedFilters: false,
      ...(hasInternalEndReached ? { internal: false } : {}),
    };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
