import { effectScope, reactive, nextTick } from 'vue';
import { flushPromises } from '@vue/test-utils';
import api from 'dashboard/api/conversations';
import { useConversationLinks } from '../useConversationLinks';
vi.mock('dashboard/api/conversations', () => ({
  default: { getLinks: vi.fn() },
}));

describe('conversation links', () => {
  let scope;
  let props;
  let state;
  beforeEach(() => {
    vi.clearAllMocks();
    props = reactive({ show: false, conversationId: 7 });
    api.getLinks.mockResolvedValue({
      data: {
        payload: [{ url: 'https://example.com' }],
        total_count: 26,
        has_more: true,
      },
    });
    scope = effectScope();
    state = scope.run(() => useConversationLinks(props));
  });
  afterEach(() => scope.stop());
  it('only loads when the gallery opens, not on conversation selection', async () => {
    props.conversationId = 8;
    await nextTick();
    expect(api.getLinks).not.toHaveBeenCalled();
    props.show = true;
    await flushPromises();
    expect(api.getLinks).toHaveBeenCalledWith(8, 1);
    expect(state.total.value).toBe(26);
    await state.load(true);
    expect(api.getLinks).toHaveBeenLastCalledWith(8, 2);
  });
  it('discards a response after the gallery closes', async () => {
    let resolve;
    api.getLinks.mockImplementation(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    props.show = true;
    await nextTick();
    props.show = false;
    await nextTick();
    resolve({
      data: { payload: [{ url: 'https://stale.example' }], total_count: 1 },
    });
    await flushPromises();
    expect(state.links.value).toEqual([]);
  });
  it('reports failure instead of a successful zero count', async () => {
    api.getLinks.mockRejectedValue(new Error('offline'));
    props.show = true;
    await flushPromises();
    expect(state.error.value).toBe(true);
  });
});
