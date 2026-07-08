/* eslint-disable no-param-reassign */
import types from '../mutation-types';
import ContactRemindersAPI from '../../api/contactReminders';
import camelcaseKeys from 'camelcase-keys';

export const state = {
  records: {},
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export const getters = {
  getAllRemindersByContact: _state => contactId => {
    const records = _state.records[contactId] || [];
    return records.sort((r1, r2) => r2.id - r1.id);
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
  getAllRemindersByContactId: _state => contactId => {
    const records = _state.records[contactId] || [];
    const contactReminders = records.sort((r1, r2) => r2.id - r1.id);
    return camelcaseKeys(contactReminders);
  },
};

export const actions = {
  async get({ commit }, { contactId }) {
    commit(types.SET_CONTACT_REMINDERS_UI_FLAG, { isFetching: true });
    try {
      const { data } = await ContactRemindersAPI.get(contactId);
      commit(types.SET_CONTACT_REMINDERS, { contactId, data });
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_CONTACT_REMINDERS_UI_FLAG, { isFetching: false });
    }
  },

  async create({ commit }, { contactId, ...payload }) {
    commit(types.SET_CONTACT_REMINDERS_UI_FLAG, { isCreating: true });
    try {
      const { data } = await ContactRemindersAPI.create(contactId, payload);
      commit(types.ADD_CONTACT_REMINDER, { contactId, data });
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_CONTACT_REMINDERS_UI_FLAG, { isCreating: false });
    }
  },

  async update({ commit }, { contactId, reminderId, ...payload }) {
    commit(types.SET_CONTACT_REMINDERS_UI_FLAG, { isUpdating: true });
    try {
      const { data } = await ContactRemindersAPI.update(
        contactId,
        reminderId,
        payload
      );
      commit(types.EDIT_CONTACT_REMINDER, { contactId, data });
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_CONTACT_REMINDERS_UI_FLAG, { isUpdating: false });
    }
  },

  async delete({ commit }, { reminderId, contactId }) {
    commit(types.SET_CONTACT_REMINDERS_UI_FLAG, { isDeleting: true });
    try {
      await ContactRemindersAPI.delete(contactId, reminderId);
      commit(types.DELETE_CONTACT_REMINDER, { contactId, reminderId });
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_CONTACT_REMINDERS_UI_FLAG, { isDeleting: false });
    }
  },
};

export const mutations = {
  [types.SET_CONTACT_REMINDERS_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },

  [types.SET_CONTACT_REMINDERS]($state, { data, contactId }) {
    $state.records = {
      ...$state.records,
      [contactId]: data,
    };
  },
  [types.ADD_CONTACT_REMINDER]($state, { data, contactId }) {
    const contactReminders = $state.records[contactId] || [];
    $state.records[contactId] = [...contactReminders, data];
  },
  [types.EDIT_CONTACT_REMINDER]($state, { data, contactId }) {
    const contactReminders = $state.records[contactId] || [];
    const index = contactReminders.findIndex(
      reminder => reminder.id === data.id
    );
    if (index !== -1) {
      contactReminders[index] = data;
      $state.records[contactId] = [...contactReminders];
    }
  },
  [types.DELETE_CONTACT_REMINDER]($state, { reminderId, contactId }) {
    const contactReminders = $state.records[contactId];
    const withoutDeletedReminder = contactReminders.filter(
      reminder => reminder.id !== reminderId
    );
    $state.records[contactId] = [...withoutDeletedReminder];
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
