import { flushPromises, mount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import NativeShareInbox from './NativeShareInbox.vue';

const mocks = vi.hoisted(() => ({
  searchConversations: vi.fn(),
}));

vi.mock('dashboard/api/search', () => ({
  default: { conversations: mocks.searchConversations },
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    getters: {
      getAllConversations: [],
      getCurrentAccountId: 1,
      'inboxes/getInbox': () => null,
    },
  }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: {} }),
  useRouter: () => ({ push: vi.fn() }),
}));

vi.mock('../platform/nativeShareService', async () => {
  const { readonly, ref } = await import('vue');
  const pendingShare = ref({ files: [], text: 'Conteúdo' });

  return {
    consumePendingShare: vi.fn(),
    dismissPendingShare: vi.fn(),
    initializeNativeShare: vi.fn(),
    usePendingNativeShare: () => readonly(pendingShare),
  };
});

const deferred = () => {
  let resolve;
  const promise = new Promise(resolvePromise => {
    resolve = resolvePromise;
  });
  return { promise, resolve };
};

const searchResponse = (id, name, thumbnail) => ({
  data: {
    payload: {
      conversations: [{ id, contact: { id, name, thumbnail } }],
    },
  },
});

const mountComponent = () =>
  mount(NativeShareInbox, {
    global: {
      stubs: {
        Avatar: {
          props: ['name', 'src'],
          template:
            '<img data-testid="contact-avatar" :alt="name" :src="src" />',
        },
      },
    },
  });

describe('NativeShareInbox', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    mocks.searchConversations.mockReset();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('clears the previous avatar and ignores an older search response', async () => {
    const firstSearch = deferred();
    const outdatedSearch = deferred();
    const latestSearch = deferred();
    mocks.searchConversations
      .mockReturnValueOnce(firstSearch.promise)
      .mockReturnValueOnce(outdatedSearch.promise)
      .mockReturnValueOnce(latestSearch.promise);

    const wrapper = mountComponent();
    const input = wrapper.get('input[type="search"]');

    await input.setValue('Maria');
    await vi.advanceTimersByTimeAsync(300);
    firstSearch.resolve(searchResponse(1, 'Maria', 'https://img.test/maria'));
    await flushPromises();

    expect(
      wrapper.get('[data-testid="contact-avatar"]').attributes('src')
    ).toBe('https://img.test/maria');

    await input.setValue('Joana');
    expect(wrapper.find('[data-testid="contact-avatar"]').exists()).toBe(false);
    await vi.advanceTimersByTimeAsync(300);

    await input.setValue('Carla');
    await vi.advanceTimersByTimeAsync(300);
    latestSearch.resolve(searchResponse(3, 'Carla', 'https://img.test/carla'));
    await flushPromises();

    outdatedSearch.resolve(
      searchResponse(2, 'Joana', 'https://img.test/joana')
    );
    await flushPromises();

    const avatar = wrapper.get('[data-testid="contact-avatar"]');
    expect(avatar.attributes('alt')).toBe('Carla');
    expect(avatar.attributes('src')).toBe('https://img.test/carla');
  });
});
