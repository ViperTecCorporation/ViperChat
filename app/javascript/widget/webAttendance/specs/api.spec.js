import { attachmentUrl, mergeMessages, request, takeInvitation } from '../api';

describe('attendance API', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('removes the fragment without sending the secret to history', () => {
    const history = { state: null, replaceState: vi.fn() };
    expect(
      takeInvitation(
        {
          hash: '#token=secret',
          pathname: '/web-attendance',
          search: '?lang=en',
        },
        history
      )
    ).toBe('secret');
    expect(history.replaceState).toHaveBeenCalledWith(
      null,
      '',
      '/web-attendance?lang=en'
    );
  });

  it('keeps loaded history and deduplicates updated messages', () => {
    expect(
      mergeMessages(
        [{ id: 1 }, { id: 2, content: 'old' }],
        [{ id: 3 }, { id: 2, content: 'updated' }]
      )
    ).toEqual([{ id: 1 }, { id: 2, content: 'updated' }, { id: 3 }]);
  });

  it.each([
    'https://other.example/web-attendance/api/attachments/1',
    // Deliberately malicious input: it must never become a rendered link.
    // eslint-disable-next-line no-script-url
    'javascript:alert(1)',
    '/rails/active_storage/blobs/1',
    '/web-attendance/api/session',
    '//other.example/file',
  ])('blocks unsafe attachment URL %s', value => {
    expect(attachmentUrl(value, 'https://chat.example')).toBe('');
  });

  it('accepts only same-origin cookie-authorized attachment paths', () => {
    expect(
      attachmentUrl(
        'https://chat.example/web-attendance/api/attachments/12?download=1',
        'https://chat.example'
      )
    ).toBe('/web-attendance/api/attachments/12?download=1');
  });

  it('accepts the empty 201 from the session exchange and sends the required header', async () => {
    const fetch = vi
      .fn()
      .mockResolvedValue({ ok: true, status: 201, text: async () => '' });
    vi.stubGlobal('fetch', fetch);
    expect(
      await request('/session', { method: 'POST', body: { token: 'secret' } })
    ).toBeNull();
    expect(fetch).toHaveBeenCalledWith(
      '/web-attendance/api/session',
      expect.objectContaining({
        credentials: 'same-origin',
        cache: 'no-store',
        headers: expect.objectContaining({ 'X-Web-Attendance': '1' }),
        body: '{"token":"secret"}',
      })
    );
  });

  it('does not override multipart boundaries', async () => {
    const fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 201,
      text: async () => '{"id":1}',
    });
    vi.stubGlobal('fetch', fetch);
    const body = new FormData();
    await request('/messages', { method: 'POST', body });
    expect(fetch.mock.calls[0][1].headers['Content-Type']).toBeUndefined();
    expect(fetch.mock.calls[0][1].body).toBe(body);
  });

  it('preserves revocation status', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({ ok: false, status: 410 })
    );
    await expect(request('/session')).rejects.toMatchObject({ status: 410 });
  });

  it('sends absent presence with cookie, header and keepalive without a cancellable signal or token', async () => {
    const fetch = vi
      .fn()
      .mockResolvedValue({ ok: true, status: 204, text: async () => '' });
    vi.stubGlobal('fetch', fetch);
    const body = {
      visible: false,
      presence_id: '7ff618f7-7e22-4a76-98df-dcaa998b54a0',
    };
    const closing = new AbortController();
    closing.abort();
    await request('/presence', {
      method: 'POST',
      body,
      keepalive: true,
      signal: closing.signal,
    });
    expect(fetch).toHaveBeenCalledWith('/web-attendance/api/presence', {
      method: 'POST',
      credentials: 'same-origin',
      cache: 'no-store',
      keepalive: true,
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'X-Web-Attendance': '1',
      },
      body: JSON.stringify(body),
    });
    expect(fetch.mock.calls[0][1]).not.toHaveProperty('signal');
    expect(fetch.mock.calls[0][1].body).not.toContain('token');
  });
});
