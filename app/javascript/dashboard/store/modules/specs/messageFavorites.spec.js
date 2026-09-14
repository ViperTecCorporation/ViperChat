import { createStore } from 'vuex';
import favorites from '../messageFavorites';
import api from 'dashboard/api/messageFavorites';
vi.mock('dashboard/api/messageFavorites', () => ({
  default: { list: vi.fn(), favorite: vi.fn(), unfavorite: vi.fn() },
}));

const makeStore = () =>
  createStore({
    state: { user: 1, account: 1 },
    getters: {
      getCurrentUser: state => ({ id: state.user }),
      getCurrentAccountId: state => state.account,
    },
    modules: { messageFavorites: favorites },
  });

describe('message favorites', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.list.mockResolvedValue({ data: { ids: [10] } });
  });
  it('loads ids only once for all bubbles of the same conversation', async () => {
    const store = makeStore();
    await Promise.all([
      store.dispatch('messageFavorites/load', 2),
      store.dispatch('messageFavorites/load', 2),
    ]);
    expect(api.list).toHaveBeenCalledTimes(1);
    expect(store.getters['messageFavorites/isFavorite'](2, 10)).toBe(true);
  });
  it('never mixes accounts or users', async () => {
    const store = makeStore();
    await store.dispatch('messageFavorites/load', 2);
    store.state.account = 2;
    expect(store.getters['messageFavorites/isFavorite'](2, 10)).toBe(false);
    store.state.account = 1;
    store.state.user = 2;
    expect(store.getters['messageFavorites/isFavorite'](2, 10)).toBe(false);
  });
  it('adds and removes only after a successful server response', async () => {
    const store = makeStore();
    await store.dispatch('messageFavorites/load', 2);
    api.unfavorite.mockRejectedValueOnce(new Error('offline'));
    const payload = { conversationId: 2, messageId: 10, favorite: false };
    await expect(
      store.dispatch('messageFavorites/setFavorite', payload)
    ).rejects.toThrow();
    expect(store.getters['messageFavorites/isFavorite'](2, 10)).toBe(true);
    await store.dispatch('messageFavorites/setFavorite', payload);
    expect(store.getters['messageFavorites/isFavorite'](2, 10)).toBe(false);
    await store.dispatch('messageFavorites/setFavorite', {
      ...payload,
      favorite: true,
    });
    expect(api.favorite).toHaveBeenCalledWith(10);
    expect(store.getters['messageFavorites/isFavorite'](2, 10)).toBe(true);
  });
  it('retries loading after failure', async () => {
    const store = makeStore();
    api.list.mockRejectedValueOnce(new Error('offline'));
    await expect(store.dispatch('messageFavorites/load', 2)).rejects.toThrow();
    await store.dispatch('messageFavorites/load', 2);
    expect(store.getters['messageFavorites/isFavorite'](2, 10)).toBe(true);
  });
});
