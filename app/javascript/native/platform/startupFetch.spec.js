import { startupFetch } from './startupFetch';

describe('startupFetch', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.useRealTimers();
  });

  it('aborts an unreachable server after eight seconds', async () => {
    vi.useFakeTimers();
    vi.stubGlobal(
      'fetch',
      vi.fn(
        (_url, { signal }) =>
          new Promise((_resolve, reject) => {
            signal.addEventListener('abort', () =>
              reject(new Error('aborted'))
            );
          })
      )
    );
    const pending = expect(
      startupFetch('https://example.test')
    ).rejects.toThrow('aborted');
    await vi.advanceTimersByTimeAsync(8000);
    await pending;
    expect(vi.getTimerCount()).toBe(0);
  });

  it('returns the response and removes its timer on success', async () => {
    vi.useFakeTimers();
    const response = { ok: true };
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(response));
    expect(await startupFetch('https://example.test')).toBe(response);
    expect(vi.getTimerCount()).toBe(0);
  });
});
