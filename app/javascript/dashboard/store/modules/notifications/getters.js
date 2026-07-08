import { sortComparator } from './helpers';
import camelcaseKeys from 'camelcase-keys';

export const getters = {
  getNotifications($state) {
    return Object.values($state.records).sort((n1, n2) => n2.id - n1.id);
  },
  getFilteredNotifications: $state => (overrideFilters = {}) => {
    const filters = { ...$state.notificationFilters, ...overrideFilters };
    const sortOrder = filters.sortOrder === 'desc' ? 'newest' : 'oldest';
    let sortedNotifications = Object.values($state.records).sort((n1, n2) =>
      sortComparator(n1, n2, sortOrder)
    );

    // Filter by read/unread status
    if (filters.type === 'read') {
      sortedNotifications = sortedNotifications.filter(
        n => n.read_at || n.readAt
      );
    } else {
      sortedNotifications = sortedNotifications.filter(
        n => !n.read_at && !n.readAt
      );
    }

    // Filter by status (snoozed/active)
    if (filters.status === 'snoozed') {
      sortedNotifications = sortedNotifications.filter(
        n => n.snoozed_until || n.snoozedUntil
      );
    } else {
      sortedNotifications = sortedNotifications.filter(
        n => !n.snoozed_until && !n.snoozedUntil
      );
    }

    return sortedNotifications;
  },
  getFilteredNotificationsV4: ($state, getters) => (overrideFilters = {}) => {
    const notifications = getters.getFilteredNotifications(overrideFilters);
    return camelcaseKeys(notifications, { deep: true });
  },
  getNotificationById: $state => id => {
    return $state.records[id] || {};
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
  getNotification: $state => id => {
    const notification = $state.records[id];
    return notification || {};
  },
  getMeta: $state => {
    return $state.meta;
  },
  getNotificationFilters($state) {
    return $state.notificationFilters;
  },
  getHasUnreadNotifications: $state => {
    return $state.meta.unreadCount > 0;
  },
  getUnreadCount: $state => {
    return $state.meta.unreadCount;
  },
};
