import { mountWebApp } from '../mountWebApp';

describe('web startup splash', () => {
  beforeEach(async () => {
    vi.useFakeTimers();
    vi.resetModules();
    document.body.innerHTML = `
      <div id="dashboard-boot" data-session="Session" data-opening="Opening"
        data-slow="Slow" data-failed="Failed">
        <p id="dashboard-boot-status">Loading</p>
        <p id="dashboard-boot-notice" hidden></p>
        <button id="dashboard-boot-retry" hidden>Retry</button>
      </div><div id="app"></div>`;
    await import('../../../../../public/dashboard-boot-v1.js');
  });

  afterEach(() => {
    window.viperBoot?.finish();
    vi.useRealTimers();
    document.body.innerHTML = '';
  });

  it('waits for the requested route and removes the splash after mounting', async () => {
    let resolveRoute;
    const router = {
      isReady: () =>
        new Promise(resolve => {
          resolveRoute = resolve;
        }),
    };
    const app = { mount: vi.fn() };
    const originalUrl = window.location.href;
    const pending = mountWebApp(app, router);
    expect(document.getElementById('dashboard-boot-status').textContent).toBe(
      'Session'
    );
    expect(app.mount).not.toHaveBeenCalled();
    resolveRoute();
    await pending;
    expect(app.mount).toHaveBeenCalledWith('#app');
    await vi.advanceTimersByTimeAsync(32);
    expect(document.getElementById('dashboard-boot')).toBeNull();
    expect(window.location.href).toBe(originalUrl);
    await vi.advanceTimersByTimeAsync(60000);
    expect(window.viperBoot).toBeUndefined();
  });

  it('offers manual retry on a slow start but still permits completion', () => {
    vi.advanceTimersByTime(45000);
    expect(document.getElementById('dashboard-boot-notice').textContent).toBe(
      'Slow'
    );
    expect(document.getElementById('dashboard-boot-retry').hidden).toBe(false);
    window.viperBoot.finish();
    expect(document.getElementById('dashboard-boot')).toBeNull();
  });

  it('keeps a recoverable error visible when routing fails', async () => {
    const app = { mount: vi.fn() };
    await expect(
      mountWebApp(app, { isReady: () => Promise.reject(new Error('offline')) })
    ).rejects.toThrow('offline');
    expect(app.mount).not.toHaveBeenCalled();
    expect(document.getElementById('dashboard-boot-notice').textContent).toBe(
      'Failed'
    );
    expect(document.getElementById('dashboard-boot-retry').hidden).toBe(false);
  });

  it('reports a failed module download', () => {
    window.dispatchEvent(new Event('vite:preloadError'));
    expect(document.getElementById('dashboard-boot-notice').textContent).toBe(
      'Failed'
    );
  });
});
