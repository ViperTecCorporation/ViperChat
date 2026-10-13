import { defineComponent, h } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { AttendanceError, request } from '../api';
import { useAttendance } from '../useAttendance';

vi.mock('../api', async importOriginal => ({
  ...(await importOriginal()),
  request: vi.fn(),
}));

describe('visitor session lifecycle', () => {
  let wrapper;
  let attendance;
  beforeEach(() => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({ ok: true, status: 204 })
    );
    request.mockImplementation(async path => {
      if (path.startsWith('/session')) {
        return {
          name: 'Support',
          contact_name: 'Visitor',
          messages: [
            { id: 5, content: 'Hello', message_type: 1, status: 'delivered' },
          ],
          has_more: true,
        };
      }
      return path === '/messages'
        ? { id: 6, message_type: 0, status: 'sent', content: 'My draft' }
        : null;
    });
  });
  afterEach(() => {
    wrapper?.unmount();
    vi.unstubAllGlobals();
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  const AttendanceHarness = defineComponent({
    props: { invitation: { type: String, default: null } },
    setup(props) {
      attendance = useAttendance(props.invitation);
      return () => h('div');
    },
  });

  function start(invitation = null) {
    wrapper = mount(AttendanceHarness, { props: { invitation } });
    return flushPromises();
  }

  it('exchanges a token before fetching history and marking it seen', async () => {
    await start('invite');
    expect(request.mock.calls.map(([path]) => path)).toEqual([
      '/session',
      '/session',
      '/seen',
      '/presence',
    ]);
    expect(request.mock.calls[0][1]).toMatchObject({
      method: 'POST',
      body: { token: 'invite' },
    });
    expect(attendance.state.value).toBe('active');
  });

  it('keeps the invitation for an explicit retry after a network failure', async () => {
    request.mockRejectedValueOnce(new TypeError('Network unavailable'));
    await start('invite');
    expect(attendance.state.value).toBe('offline');
    await attendance.refresh();
    expect(request.mock.calls[1][1].body).toEqual({ token: 'invite' });
    expect(attendance.state.value).toBe('active');
  });

  it('retains drafts and uploaded files and reuses the request UUID on retry', async () => {
    await start();
    attendance.draft.value = 'My draft';
    const file = new File(['image'], 'image.png', { type: 'image/png' });
    attendance.addFiles([file]);
    request.mockRejectedValueOnce(new TypeError('Connection lost'));
    await attendance.send();
    expect(attendance.draft.value).toBe('My draft');
    expect(attendance.files.value[0]).toBe(file);
    expect(attendance.error.value).toBe('failed');
    const firstSend = request.mock.calls.find(
      ([path]) => path === '/messages'
    )[1].body;
    await attendance.send();
    const secondSend = request.mock.calls.filter(
      ([path]) => path === '/messages'
    )[1][1].body;
    expect(secondSend.get('request_id')).toBe(firstSend.get('request_id'));
    expect(secondSend.getAll('attachments[]')).toHaveLength(1);
    expect(attendance.draft.value).toBe('');
    expect(attendance.files.value).toEqual([]);
  });

  it('retains older pages during polling', async () => {
    await start();
    request.mockResolvedValueOnce({ messages: [{ id: 2 }], has_more: false });
    await attendance.older();
    await attendance.refresh();
    expect(attendance.messages.value.map(message => message.id)).toEqual([
      2, 5,
    ]);
    expect(attendance.hasMore.value).toBe(false);
  });

  it('keeps the POST audio bubble through stale polling, failed refresh and later receipt updates', async () => {
    await start();
    attendance.addFiles([
      new File(['audio'], 'voice.webm', { type: 'audio/webm' }),
    ]);
    const message = {
      id: 6,
      message_type: 0,
      created_at: 1,
      status: 'sent',
      attachments: [
        { id: 8, file_type: 'audio', url: '/web-attendance/api/attachments/8' },
      ],
    };
    request.mockResolvedValueOnce(message);
    request.mockRejectedValueOnce(new TypeError('Poll failed'));
    await attendance.send();
    expect(attendance.messages.value.at(-1)).toEqual(message);
    expect(attendance.files.value).toEqual([]);
    await attendance.refresh();
    expect(attendance.messages.value.at(-1)).toEqual(message);
    request.mockResolvedValueOnce({
      messages: [{ ...message, status: 'read' }],
    });
    await attendance.refresh();
    expect(
      attendance.messages.value.filter(item => item.id === 6)
    ).toHaveLength(1);
    expect(attendance.messages.value.at(-1).status).toBe('read');
  });

  it('keeps the draft and attachment when the POST omits its persisted presenter', async () => {
    await start();
    attendance.draft.value = 'Audio note';
    attendance.addFiles([new File(['audio'], 'voice.webm')]);
    request.mockResolvedValueOnce(null);
    await attendance.send();
    expect(attendance.draft.value).toBe('Audio note');
    expect(attendance.files.value).toHaveLength(1);
    expect(attendance.error.value).toBe('failed');
  });

  it('displays an audio-only presenter already READ without losing it to an empty session page', async () => {
    await start();
    attendance.addFiles([
      new File(['fixture'], 'voice.webm', { type: 'audio/webm' }),
    ]);
    const persisted = {
      id: 2416117,
      content: null,
      message_type: 0,
      created_at: 1,
      status: 'read',
      delivery_destination: 'web',
      attachments: [
        {
          id: 291645,
          file_type: 'audio',
          url: '/web-attendance/api/attachments/291645',
        },
      ],
    };
    request.mockResolvedValueOnce(persisted);
    request.mockResolvedValueOnce({ messages: [] });
    await attendance.send();
    expect(attendance.messages.value.at(-1)).toEqual(persisted);
    expect(attendance.files.value).toEqual([]);
  });

  describe('recording controls', () => {
    let trackStop;
    let microphoneStream;
    beforeEach(() => {
      trackStop = vi.fn();
      microphoneStream = { getTracks: () => [{ stop: trackStop }] };
      vi.stubGlobal('navigator', {
        mediaDevices: {
          getUserMedia: vi.fn().mockResolvedValue(microphoneStream),
        },
      });
      vi.stubGlobal('URL', {
        createObjectURL: vi.fn(() => 'blob:voice'),
        revokeObjectURL: vi.fn(),
      });
      const Recorder = vi.fn((stream, options) => ({
        mimeType: options.mimeType,
        state: 'inactive',
        start() {
          this.state = 'recording';
        },
        stop() {
          this.state = 'inactive';
          this.ondataavailable({
            data: new Blob(['voice'], { type: this.mimeType }),
          });
          this.onstop();
        },
      }));
      Recorder.isTypeSupported = type => type.startsWith('audio/webm');
      vi.stubGlobal('MediaRecorder', Recorder);
    });

    it('shares the active microphone with the waveform and discards a cancelled recording', async () => {
      await start();
      await attendance.startRecording();
      expect(attendance.recordingStream.value).toBe(microphoneStream);
      attendance.cancelRecording();
      expect(attendance.recordingStream.value).toBe(null);
      expect(attendance.recording.value).toBe(false);
      expect(attendance.files.value).toEqual([]);
      expect(attendance.voiceUrl.value).toBe('');
      expect(trackStop).toHaveBeenCalled();
      await attendance.startRecording();
      attendance.stopRecording();
      expect(attendance.files.value).toHaveLength(1);
    });

    it('stops a microphone permission request resolved after cancellation without creating a file', async () => {
      let resolvePermission;
      navigator.mediaDevices.getUserMedia.mockImplementationOnce(
        () =>
          new Promise(resolve => {
            resolvePermission = resolve;
          })
      );
      await start();
      const pending = attendance.startRecording();
      attendance.cancelRecording();
      resolvePermission(microphoneStream);
      await pending;
      expect(trackStop).toHaveBeenCalled();
      expect(attendance.recordingStream.value).toBe(null);
      expect(attendance.startingRecording.value).toBe(false);
      expect(attendance.files.value).toEqual([]);
    });

    it('only clears the preview when removing its recorded file, and can record again after delete', async () => {
      await start();
      attendance.addFiles([new File(['x'], 'other.txt')]);
      await attendance.startRecording();
      attendance.stopRecording();
      attendance.removeFile(0);
      expect(attendance.voiceUrl.value).toBe('blob:voice');
      expect(URL.revokeObjectURL).not.toHaveBeenCalled();
      attendance.removeVoice();
      expect(attendance.files.value).toEqual([]);
      expect(attendance.voiceUrl.value).toBe('');
      expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:voice');
      await attendance.startRecording();
      attendance.stopRecording();
      attendance.removeFile(0);
      expect(attendance.voiceUrl.value).toBe('');
      expect(attendance.files.value).toEqual([]);
    });

    it('preserves the recorded preview on upload failure and releases it after accepted retry', async () => {
      await start();
      await attendance.startRecording();
      attendance.stopRecording();
      request.mockRejectedValueOnce(new TypeError('Upload failed'));
      await attendance.send();
      expect(attendance.voiceUrl.value).toBe('blob:voice');
      expect(attendance.files.value).toHaveLength(1);
      expect(URL.revokeObjectURL).not.toHaveBeenCalled();
      await attendance.send();
      expect(attendance.voiceUrl.value).toBe('');
      expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:voice');
    });
  });

  it('clears history and drafts on 410 and stops subsequent retries', async () => {
    await start();
    attendance.draft.value = 'private draft';
    attendance.addFiles([new File(['x'], 'file.txt')]);
    request.mockRejectedValueOnce(new AttendanceError(410));
    await attendance.refresh();
    expect(attendance.state.value).toBe('ended');
    expect(attendance.messages.value).toEqual([]);
    expect(attendance.files.value).toEqual([]);
    expect(attendance.draft.value).toBe('');
    const calls = request.mock.calls.length;
    await attendance.refresh();
    await attendance.send();
    expect(request.mock.calls).toHaveLength(calls);
  });

  it('cannot restore messages from an in-flight page after revocation', async () => {
    await start();
    let resolvePage;
    request.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolvePage = resolve;
        })
    );
    const pending = attendance.older();
    request.mockRejectedValueOnce(new AttendanceError(410));
    await attendance.refresh();
    resolvePage({ messages: [{ id: 1, content: 'secret' }], has_more: false });
    await pending;
    expect(attendance.messages.value).toEqual([]);
    expect(attendance.state.value).toBe('ended');
  });

  it('rejects more than five attachments without discarding selected files', async () => {
    await start();
    const selected = Array.from(
      { length: 5 },
      () => new File(['x'], 'file.txt')
    );
    attendance.addFiles(selected);
    attendance.addFiles([new File(['x'], 'extra.txt')]);
    expect(attendance.files.value).toHaveLength(5);
    expect(attendance.error.value).toBe('limit');
  });

  it('stops microphone tracks when permission resolves after closing the page', async () => {
    let resolvePermission;
    const stop = vi.fn();
    vi.stubGlobal('navigator', {
      mediaDevices: {
        getUserMedia: vi.fn(
          () =>
            new Promise(resolve => {
              resolvePermission = resolve;
            })
        ),
      },
    });
    vi.stubGlobal('MediaRecorder', vi.fn());
    await start();
    const pending = attendance.startRecording();
    wrapper.unmount();
    wrapper = null;
    resolvePermission({ getTracks: () => [{ stop }] });
    await pending;
    expect(stop).toHaveBeenCalledOnce();
    expect(attendance.files.value).toEqual([]);
  });

  it('polls every three seconds and stops after revocation', async () => {
    vi.useFakeTimers();
    await start();
    const calls = request.mock.calls.length;
    await vi.advanceTimersByTimeAsync(3000);
    expect(request.mock.calls.length).toBe(calls + 2);
    request.mockRejectedValueOnce(new AttendanceError(410));
    await vi.advanceTimersByTimeAsync(3000);
    const revokedCalls = request.mock.calls.length;
    await vi.advanceTimersByTimeAsync(12000);
    expect(request.mock.calls.length).toBe(revokedCalls);
    expect(attendance.state.value).toBe('ended');
  });

  it('acks a changed agent status even with a newer visitor message, without a polling loop', async () => {
    vi.useFakeTimers();
    const agent = { id: 4, message_type: 1, status: 'sent' };
    const visitor = { id: 5, message_type: 0, status: 'sent' };
    request.mockImplementation(async path =>
      path.startsWith('/session')
        ? { messages: [{ ...agent }, { ...visitor }] }
        : null
    );
    await start();
    expect(
      request.mock.calls.filter(([path]) => path === '/seen')
    ).toHaveLength(1);
    agent.status = 'delivered';
    await vi.advanceTimersByTimeAsync(3000);
    expect(
      request.mock.calls.filter(([path]) => path === '/seen')
    ).toHaveLength(2);
    await vi.advanceTimersByTimeAsync(12000);
    expect(
      request.mock.calls.filter(([path]) => path === '/seen')
    ).toHaveLength(2);
    agent.status = 'read';
    visitor.status = 'read';
    await vi.advanceTimersByTimeAsync(3000);
    expect(attendance.messages.value.map(message => message.status)).toEqual([
      'read',
      'read',
    ]);
    expect(
      request.mock.calls.filter(([path]) => path === '/seen')
    ).toHaveLength(2);
    agent.status = 'delivered';
    await attendance.refresh();
    expect(
      request.mock.calls.filter(([path]) => path === '/seen')
    ).toHaveLength(3);
  });

  it.each(['sent', 'delivered', 'progress'])(
    'acks unread agent %s only once',
    async status => {
      request.mockImplementation(async path =>
        path.startsWith('/session')
          ? { messages: [{ id: 5, message_type: 1, status }] }
          : null
      );
      await start();
      await attendance.refresh();
      expect(
        request.mock.calls.filter(([path]) => path === '/seen')
      ).toHaveLength(1);
    }
  );

  it('does not ack visitor messages or already-read agent messages', async () => {
    request.mockImplementation(async path =>
      path.startsWith('/session')
        ? {
            messages: [
              { id: 1, message_type: 1, status: 'read' },
              { id: 2, message_type: 0, status: 'sent' },
              { id: 3, message_type: 0, status: 'delivered' },
            ],
          }
        : null
    );
    await start();
    await attendance.refresh();
    expect(request.mock.calls.some(([path]) => path === '/seen')).toBe(false);
  });

  it('retries failed acknowledgements and then suppresses duplicates', async () => {
    request.mockImplementation(async path => {
      if (path === '/seen') throw new TypeError('Connection lost');
      return { messages: [{ id: 5, message_type: 1, status: 'delivered' }] };
    });
    await start();
    expect(attendance.state.value).toBe('offline');
    request.mockImplementation(async path =>
      path === '/seen'
        ? null
        : { messages: [{ id: 5, message_type: 1, status: 'delivered' }] }
    );
    await attendance.refresh();
    await attendance.refresh();
    expect(attendance.state.value).toBe('active');
    expect(
      request.mock.calls.filter(([path]) => path === '/seen')
    ).toHaveLength(2);
  });

  it('acks again after reconnecting with the same message ID and status', async () => {
    await start();
    request.mockRejectedValueOnce(new TypeError('Offline'));
    await attendance.refresh();
    await attendance.refresh();
    await attendance.refresh();
    expect(
      request.mock.calls.filter(([path]) => path === '/seen')
    ).toHaveLength(2);
    window.dispatchEvent(new Event('online'));
    await flushPromises();
    await attendance.refresh();
    expect(
      request.mock.calls.filter(([path]) => path === '/seen')
    ).toHaveLength(3);
  });

  it('defers ack while hidden and resumes once when visible, including an unchanged ID', async () => {
    vi.useFakeTimers();
    const hidden = vi.spyOn(document, 'hidden', 'get').mockReturnValue(true);
    await start();
    expect(request.mock.calls.some(([path]) => path === '/seen')).toBe(false);
    hidden.mockReturnValue(false);
    document.dispatchEvent(new Event('visibilitychange'));
    await flushPromises();
    expect(
      request.mock.calls.filter(([path]) => path === '/seen')
    ).toHaveLength(1);
    hidden.mockReturnValue(true);
    document.dispatchEvent(new Event('visibilitychange'));
    const calls = request.mock.calls.length;
    await vi.advanceTimersByTimeAsync(12000);
    expect(request.mock.calls).toHaveLength(calls);
    hidden.mockReturnValue(false);
    document.dispatchEvent(new Event('visibilitychange'));
    await flushPromises();
    await vi.advanceTimersByTimeAsync(9000);
    expect(
      request.mock.calls.filter(([path]) => path === '/seen')
    ).toHaveLength(2);
  });

  it('acks an unread agent message received in an older page', async () => {
    await start();
    request.mockResolvedValueOnce({
      messages: [{ id: 2, message_type: 1, status: 'progress' }],
      has_more: false,
    });
    await attendance.older();
    await attendance.refresh();
    expect(
      request.mock.calls.filter(([path]) => path === '/seen')
    ).toHaveLength(2);
  });

  it('creates an audio attachment and releases its preview and microphone on close', async () => {
    const stop = vi.fn();
    const revokeObjectURL = vi.fn();
    vi.stubGlobal('navigator', {
      mediaDevices: {
        getUserMedia: vi
          .fn()
          .mockResolvedValue({ getTracks: () => [{ stop }] }),
      },
    });
    vi.stubGlobal('URL', {
      createObjectURL: vi.fn(() => 'blob:recording'),
      revokeObjectURL,
    });
    vi.stubGlobal(
      'MediaRecorder',
      class {
        static isTypeSupported(type) {
          return type.startsWith('audio/webm');
        }

        constructor(stream, options) {
          this.mimeType = options.mimeType;
          this.state = 'inactive';
        }

        start() {
          this.state = 'recording';
        }

        stop() {
          this.state = 'inactive';
          this.ondataavailable({
            data: new Blob(['recorded bytes'], { type: this.mimeType }),
          });
          this.onstop();
        }
      }
    );
    await start();
    await attendance.startRecording();
    expect(attendance.recording.value).toBe(true);
    attendance.stopRecording();
    expect(attendance.files.value[0].type).toBe('audio/webm;codecs=opus');
    expect(attendance.files.value[0].name).toMatch(/\.webm$/);
    expect(attendance.voiceUrl.value).toBe('blob:recording');
    wrapper.unmount();
    wrapper = null;
    expect(stop).toHaveBeenCalled();
    expect(revokeObjectURL).toHaveBeenCalledWith('blob:recording');
  });

  it('posts visible presence once per three-second poll without repeating read ACKs', async () => {
    vi.useFakeTimers();
    await start();
    await vi.advanceTimersByTimeAsync(9000);
    const heartbeats = request.mock.calls.filter(
      ([path]) => path === '/presence'
    );
    expect(heartbeats).toHaveLength(4);
    const presenceId = heartbeats[0][1].body.presence_id;
    expect(presenceId).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    );
    heartbeats.forEach(([, options]) => {
      expect(options).toMatchObject({
        method: 'POST',
        body: { visible: true, presence_id: presenceId },
      });
      expect(options.body).not.toHaveProperty('token');
    });
    expect(
      request.mock.calls.filter(([path]) => path === '/seen')
    ).toHaveLength(1);
    expect(attendance.messages.value[0].status).toBe('delivered');
  });

  it('posts hidden presence with cookie headers and keepalive, stops polls, and resumes visible', async () => {
    vi.useFakeTimers();
    const hidden = vi.spyOn(document, 'hidden', 'get').mockReturnValue(false);
    await start('invite');
    hidden.mockReturnValue(true);
    document.dispatchEvent(new Event('visibilitychange'));
    const presenceId = request.mock.calls.find(
      ([path]) => path === '/presence'
    )[1].body.presence_id;
    expect(request).toHaveBeenCalledWith('/presence', {
      method: 'POST',
      keepalive: true,
      body: { visible: false, presence_id: presenceId },
    });
    const calls = request.mock.calls.length;
    await vi.advanceTimersByTimeAsync(9000);
    expect(request.mock.calls).toHaveLength(calls);
    hidden.mockReturnValue(false);
    document.dispatchEvent(new Event('visibilitychange'));
    await flushPromises();
    expect(
      request.mock.calls.filter(([path]) => path === '/presence').at(-1)[1].body
    ).toEqual({ visible: true, presence_id: presenceId });
    await vi.advanceTimersByTimeAsync(3000);
    expect(request.mock.calls.length).toBeGreaterThan(calls);
  });

  it('posts absent presence on pagehide and unmount and resumes after a bfcache pageshow', async () => {
    vi.useFakeTimers();
    await start();
    const presenceId = request.mock.calls.find(
      ([path]) => path === '/presence'
    )[1].body.presence_id;
    window.dispatchEvent(new Event('pagehide'));
    expect(
      request.mock.calls.filter(
        ([path, options]) => path === '/presence' && !options.body.visible
      )
    ).toHaveLength(1);
    const calls = request.mock.calls.length;
    await vi.advanceTimersByTimeAsync(9000);
    expect(request.mock.calls).toHaveLength(calls);
    window.dispatchEvent(new Event('pageshow'));
    await flushPromises();
    expect(
      request.mock.calls.filter(([path]) => path === '/presence').at(-1)[1].body
    ).toEqual({ visible: true, presence_id: presenceId });
    wrapper.unmount();
    wrapper = null;
    const absent = request.mock.calls.filter(
      ([path, options]) => path === '/presence' && !options.body.visible
    );
    expect(absent).toHaveLength(2);
    expect(
      absent.every(
        ([, options]) =>
          options.keepalive && options.body.presence_id === presenceId
      )
    ).toBe(true);
    const closedCalls = request.mock.calls.length;
    await vi.advanceTimersByTimeAsync(9000);
    window.dispatchEvent(new Event('pageshow'));
    expect(request.mock.calls).toHaveLength(closedCalls);
  });

  it('never posts presence when session authentication fails', async () => {
    request.mockRejectedValueOnce(new TypeError('No session'));
    await start('invite');
    window.dispatchEvent(new Event('pagehide'));
    wrapper.unmount();
    wrapper = null;
    expect(request.mock.calls.some(([path]) => path === '/presence')).toBe(
      false
    );
    expect(fetch).not.toHaveBeenCalled();
  });

  it('uses different stable presence IDs for separate pages sharing the session cookie', async () => {
    vi.useFakeTimers();
    await start();
    const firstId = request.mock.calls.find(([path]) => path === '/presence')[1]
      .body.presence_id;
    const secondPage = mount(AttendanceHarness);
    try {
      await flushPromises();
      const secondId = request.mock.calls
        .filter(([path]) => path === '/presence')
        .at(-1)[1].body.presence_id;
      expect(secondId).not.toBe(firstId);
      wrapper.unmount();
      wrapper = null;
      expect(
        request.mock.calls.filter(([path]) => path === '/presence').at(-1)[1]
      ).toEqual({
        method: 'POST',
        keepalive: true,
        body: { visible: false, presence_id: firstId },
      });
      await vi.advanceTimersByTimeAsync(6000);
      const remaining = request.mock.calls
        .filter(([path]) => path === '/presence')
        .slice(-2);
      expect(remaining.map(([, options]) => options.body)).toEqual([
        { visible: true, presence_id: secondId },
        { visible: true, presence_id: secondId },
      ]);
    } finally {
      secondPage.unmount();
    }
  });

  it.each([401, 403, 410])(
    'does not post presence after session revocation %s',
    async status => {
      await start();
      request.mockRejectedValueOnce(new AttendanceError(status));
      await attendance.refresh();
      const calls = request.mock.calls.length;
      window.dispatchEvent(new Event('pagehide'));
      window.dispatchEvent(new Event('pageshow'));
      wrapper.unmount();
      wrapper = null;
      expect(request.mock.calls).toHaveLength(calls);
      expect(fetch).not.toHaveBeenCalled();
    }
  );

  it('isolates presence network failures from state and read ACKs and retries on the next poll', async () => {
    vi.useFakeTimers();
    await start();
    request.mockImplementation(async path => {
      if (path === '/presence') throw new TypeError('Heartbeat network failed');
      return { messages: [{ id: 5, message_type: 1, status: 'delivered' }] };
    });
    await vi.advanceTimersByTimeAsync(9000);
    expect(attendance.state.value).toBe('active');
    expect(
      request.mock.calls.filter(([path]) => path === '/presence')
    ).toHaveLength(4);
    expect(
      request.mock.calls.filter(([path]) => path === '/seen')
    ).toHaveLength(1);
  });

  it('bounds stalled heartbeat requests and keeps polling independently', async () => {
    vi.useFakeTimers();
    await start();
    request.mockImplementation(async (path, options) => {
      if (path === '/presence')
        return new Promise((resolve, reject) => {
          options.signal.addEventListener(
            'abort',
            () => reject(new DOMException('Aborted', 'AbortError')),
            { once: true }
          );
        });
      return { messages: [{ id: 5, message_type: 1, status: 'delivered' }] };
    });
    await vi.advanceTimersByTimeAsync(6000);
    expect(
      request.mock.calls.filter(([path]) => path === '/session')
    ).toHaveLength(3);
    expect(
      request.mock.calls.filter(([path]) => path === '/presence')
    ).toHaveLength(3);
    const pending = request.mock.calls
      .filter(([path]) => path === '/presence')
      .at(-1)[1].signal;
    window.dispatchEvent(new Event('pagehide'));
    await flushPromises();
    expect(pending.aborted).toBe(true);
    expect(
      request.mock.calls.filter(([path]) => path === '/presence').at(-1)[1]
    ).not.toHaveProperty('signal');
    expect(attendance.state.value).toBe('active');
  });

  it.each([401, 403, 410])(
    'revokes locally on presence authorization failure %s',
    async status => {
      request.mockImplementation(async path => {
        if (path === '/presence') throw new AttendanceError(status);
        return { messages: [] };
      });
      await start();
      expect(attendance.authenticated.value).toBe(false);
      expect(attendance.state.value).toBe(
        status === 410 ? 'ended' : 'unavailable'
      );
      window.dispatchEvent(new Event('pagehide'));
      expect(fetch).not.toHaveBeenCalled();
    }
  );
});
