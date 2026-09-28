import { getters } from '../../notifications/getters';
import { reactive, computed } from 'vue';
import { mutations } from '../../notifications/mutations';
import types from '../../../mutation-types';

describe('#getters', () => {
  it('reactively hides read items without removing the active conversation record', () => {
    const state = reactive({
      records: { 1: { id: 1, read_at: null, primary_actor: { id: 42 } } },
    });
    const visible = computed(() =>
      getters.getFilteredNotificationsV4(state)({ sortOrder: 'desc' })
    );
    expect(visible.value.map(item => item.id)).toEqual([1]);
    mutations[types.READ_NOTIFICATION](state, {
      id: 1,
      read_at: '2026-09-25T12:00:00Z',
    });
    expect(visible.value).toEqual([]);
    expect(
      getters.getFilteredNotifications(state)({ sortOrder: 'desc' })[0]
        .primary_actor.id
    ).toBe(42);
    mutations[types.READ_NOTIFICATION](state, { id: 1, read_at: null });
    expect(visible.value.map(item => item.id)).toEqual([1]);
  });

  it('preserves read and snoozed items only when their display options are enabled', () => {
    const state = {
      records: {
        1: { id: 1, read_at: null, snoozed_until: null },
        2: { id: 2, read_at: true, snoozed_until: null },
        3: { id: 3, read_at: null, snoozed_until: '2030-01-01' },
        4: { id: 4, read_at: true, snoozed_until: '2030-01-01' },
      },
    };
    const ids = filters =>
      getters
        .getFilteredNotificationsV4(state)(filters)
        .map(item => item.id);
    expect(ids({})).toEqual([1]);
    expect(ids({ type: 'read' })).toEqual([1, 2]);
    expect(ids({ status: 'snoozed' })).toEqual([1, 3]);
    expect(ids({ type: 'read', status: 'snoozed' })).toEqual([1, 2, 3, 4]);
    mutations[types.UPDATE_ALL_NOTIFICATIONS](state);
    expect(ids({})).toEqual([]);
    expect(ids({ type: 'read' })).toEqual([1, 2]);
  });

  it('getNotifications', () => {
    const state = {
      records: {
        1: { id: 1 },
        2: { id: 2 },
        3: { id: 3 },
      },
    };
    expect(getters.getNotifications(state)).toEqual([
      { id: 3 },
      { id: 2 },
      { id: 1 },
    ]);
  });

  it('getFilteredNotifications', () => {
    const state = {
      records: {
        1: { id: 1, read_at: '2024-02-07T11:42:39.988Z', snoozed_until: null },
        2: { id: 2, read_at: null, snoozed_until: null },
        3: {
          id: 3,
          read_at: '2024-02-07T11:42:39.988Z',
          snoozed_until: '2024-02-07T11:42:39.988Z',
        },
      },
    };
    const filters = {
      type: 'read',
      status: 'snoozed',
      sortOrder: 'desc',
    };
    expect(getters.getFilteredNotifications(state)(filters)).toEqual([
      { id: 1, read_at: '2024-02-07T11:42:39.988Z', snoozed_until: null },
      { id: 2, read_at: null, snoozed_until: null },
      {
        id: 3,
        read_at: '2024-02-07T11:42:39.988Z',
        snoozed_until: '2024-02-07T11:42:39.988Z',
      },
    ]);
  });

  it('getNotificationById', () => {
    const state = {
      records: {
        1: { id: 1 },
      },
    };
    expect(getters.getNotificationById(state)(1)).toEqual({ id: 1 });
    expect(getters.getNotificationById(state)(2)).toEqual({});
  });

  it('getUIFlags', () => {
    const state = {
      uiFlags: {
        isFetching: true,
      },
    };
    expect(getters.getUIFlags(state)).toEqual({
      isFetching: true,
    });
  });

  it('getNotification', () => {
    const state = {
      records: {
        1: { id: 1 },
      },
    };
    expect(getters.getNotification(state)(1)).toEqual({ id: 1 });
    expect(getters.getNotification(state)(2)).toEqual({});
  });

  it('getMeta', () => {
    const state = {
      meta: { unreadCount: 1 },
    };
    expect(getters.getMeta(state)).toEqual({ unreadCount: 1 });
  });

  it('getNotificationFilters', () => {
    const state = {
      notificationFilters: {
        page: 1,
        status: 'unread',
        type: 'all',
        sortOrder: 'desc',
      },
    };
    expect(getters.getNotificationFilters(state)).toEqual(
      state.notificationFilters
    );
  });

  describe('getHasUnreadNotifications', () => {
    it('should return true when there are unread notifications', () => {
      const state = {
        meta: { unreadCount: 5 },
      };
      expect(getters.getHasUnreadNotifications(state)).toBe(true);
    });

    it('should return false when there are no unread notifications', () => {
      const state = {
        meta: { unreadCount: 0 },
      };
      expect(getters.getHasUnreadNotifications(state)).toBe(false);
    });

    it('should return false when meta is empty', () => {
      const state = {
        meta: {},
      };
      expect(getters.getHasUnreadNotifications(state)).toBe(false);
    });
  });
});
