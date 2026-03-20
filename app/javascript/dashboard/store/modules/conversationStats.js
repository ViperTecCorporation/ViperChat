import types from '../mutation-types';
import ConversationApi from '../../api/inbox/conversation';
import { debounce } from '@chatwoot/utils';

const state = {
  mineCount: 0,
  unAssignedCount: 0,
  waitingCount: 0,
  allCount: 0,
  internalCount: 0,
};

export const getters = {
  getStats: $state => $state,
};

// Create a debounced version of the actual API call function
const fetchMetaData = async (commit, params) => {
  try {
    const response = await ConversationApi.meta(params);
    const {
      data: { meta },
    } = response;
    commit(types.SET_CONV_TAB_META, {
      ...meta,
      requested_assignee_type: params?.assigneeType,
      requested_conversation_type: params?.conversationType,
      requested_inbox_channel_type: params?.inboxChannelType,
    });
  } catch (error) {
    // ignore
  }
};

const debouncedFetchMetaData = debounce(fetchMetaData, 500, false, 1500);
const longDebouncedFetchMetaData = debounce(fetchMetaData, 5000, false, 10000);
const superLongDebouncedFetchMetaData = debounce(
  fetchMetaData,
  10000,
  false,
  20000
);

export const actions = {
  get: async ({ commit, state: $state }, params) => {
    if ($state.allCount > 5000) {
      superLongDebouncedFetchMetaData(commit, params);
    } else if ($state.allCount > 100) {
      longDebouncedFetchMetaData(commit, params);
    } else {
      debouncedFetchMetaData(commit, params);
    }
  },
  set({ commit }, meta) {
    commit(types.SET_CONV_TAB_META, meta);
  },
};

export const mutations = {
  [types.SET_CONV_TAB_META](
    $state,
    {
      mine_count: mineCount,
      unassigned_count: unAssignedCount,
      waiting_count: waitingCount,
      all_count: allCount,
      internal_count: internalCount,
      requested_assignee_type: requestedAssigneeType,
      requested_conversation_type: requestedConversationType,
      requested_inbox_channel_type: requestedInboxChannelType,
    } = {}
  ) {
    const isInternalRequest =
      requestedAssigneeType === 'internal' ||
      requestedConversationType === 'internal' ||
      requestedInboxChannelType === 'Channel::Internal';
    const nextInternalCount =
      internalCount === undefined || internalCount === null
        ? $state.internalCount
        : internalCount;

    if (isInternalRequest) {
      $state.internalCount = nextInternalCount || 0;
      $state.updatedOn = new Date();
      return;
    }

    $state.mineCount = mineCount || 0;
    $state.allCount = allCount || 0;
    $state.unAssignedCount = unAssignedCount || 0;
    $state.waitingCount = waitingCount || 0;
    $state.internalCount = nextInternalCount || 0;
    $state.updatedOn = new Date();
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
