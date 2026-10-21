import { AgentSipClient, rejectedCallState } from '../AgentSipClient';
import { Registerer, Inviter } from 'sip.js';

vi.mock('sip.js', () => {
  const emitter = () => {
    const listeners = new Set();
    return {
      addListener: fn => listeners.add(fn),
      removeListener: fn => listeners.delete(fn),
      emit: state => listeners.forEach(fn => fn(state)),
    };
  };
  const Agent = vi.fn(function agent(options) {
    return {
      options,
      delegate: options.delegate,
      start: vi.fn().mockResolvedValue(),
      stop: vi.fn().mockResolvedValue(),
    };
  });
  Agent.makeURI = vi.fn(value => ({ toString: () => value }));
  const Registrar = vi.fn(function registrar() {
    const instance = {
      state: 'Initial',
      stateChange: emitter(),
      register: vi.fn().mockResolvedValue(),
      unregister: vi.fn().mockResolvedValue(),
    };
    Registrar.latest = instance;
    return instance;
  });
  class Call {
    static latest;

    constructor() {
      Call.latest = this;
    }

    request = { callId: 'synthetic-sip-id' };

    state = 'Initial';

    stateChange = emitter();

    remoteIdentity = { uri: { user: '0020' } };

    invite = vi.fn().mockResolvedValue();

    accept = vi.fn().mockResolvedValue();

    progress = vi.fn().mockResolvedValue();

    reject = vi.fn().mockResolvedValue();

    cancel = vi.fn().mockResolvedValue();

    bye = vi.fn().mockResolvedValue();

    refer = vi.fn().mockResolvedValue();

    info = vi.fn().mockResolvedValue();

    sessionDescriptionHandler = {
      peerConnection: { getSenders: () => [], getReceivers: () => [] },
    };
  }
  return {
    UserAgent: Agent,
    Registerer: Registrar,
    Inviter: Call,
    RegistererState: { Registered: 'Registered' },
    SessionState: { Established: 'Established', Terminated: 'Terminated' },
  };
});

describe('AgentSipClient', () => {
  let client;
  let onCall;
  let onRegistration;
  let onError;
  let onTransfer;
  const config = {
    extension: '0010',
    username: 'auth10',
    password: 'synthetic-password',
    sip_domain: 'sip.example.test',
    wss_url: 'wss://sip.example.test/ws',
    registration_expires: 300,
    ice_servers: [],
    transfer_enabled: true,
  };

  beforeEach(() => {
    vi.useFakeTimers();
    vi.stubGlobal(
      'MediaStream',
      vi.fn(function mediaStream() {
        return { addTrack: vi.fn() };
      })
    );
    vi.spyOn(HTMLMediaElement.prototype, 'play').mockResolvedValue();
    vi.spyOn(HTMLMediaElement.prototype, 'pause').mockImplementation(() => {});
    onCall = vi.fn().mockResolvedValue();
    onRegistration = vi.fn();
    onError = vi.fn();
    onTransfer = vi.fn();
    client = new AgentSipClient({
      onCall,
      onRegistration,
      onError,
      onTransfer,
    });
  });
  afterEach(async () => {
    await client.disconnect();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    vi.useRealTimers();
  });

  async function connect() {
    const promise = client.connect(config);
    await vi.advanceTimersByTimeAsync(0);
    Registerer.latest.state = 'Registered';
    Registerer.latest.stateChange.emit('Registered');
    await promise;
  }

  it.each([false, true])(
    'persists incoming microphone denial even when SIP terminates first: %s',
    async terminatedFirst => {
      await connect();
      const incoming = new Inviter();
      const track = { stop: vi.fn() };
      incoming.sessionDescriptionHandler.peerConnection.getSenders = () => [
        { track },
      ];
      client.incoming(incoming);
      const id = client.context.client_call_id;
      incoming.accept.mockImplementation(async () => {
        if (terminatedFirst) {
          incoming.state = 'Terminated';
          incoming.stateChange.emit('Terminated');
          await vi.advanceTimersByTimeAsync(0);
        }
        throw new DOMException('Permission denied', 'NotAllowedError');
      });
      await expect(client.answer()).rejects.toThrow('microphone_denied');
      await vi.advanceTimersByTimeAsync(0);
      const failures = onCall.mock.calls
        .map(([event]) => event)
        .filter(event => event.state === 'failed');
      expect(failures).toEqual([
        expect.objectContaining({
          client_call_id: id,
          sip_call_id: 'synthetic-sip-id',
          direction: 'incoming',
          answered: false,
          finished: true,
          end_reason: 'microphone_denied',
        }),
      ]);
      expect(onCall).not.toHaveBeenCalledWith(
        expect.objectContaining({ state: 'active' })
      );
      expect(onCall).not.toHaveBeenCalledWith(
        expect.objectContaining({ state: 'awaiting_confirmation' })
      );
      expect(onError).toHaveBeenLastCalledWith('microphone_denied');
      expect(track.stop).toHaveBeenCalledOnce();
      expect(client.session).toBeNull();
      expect(client.context).toBeNull();
      expect(client.ringtone).toBeNull();
      expect(incoming.reject).toHaveBeenCalledTimes(terminatedFirst ? 0 : 1);

      const retry = new Inviter();
      client.incoming(retry);
      await client.answer();
      retry.state = 'Established';
      retry.stateChange.emit('Established');
      expect(retry.accept).toHaveBeenCalledOnce();
      expect(onCall).toHaveBeenLastCalledWith(
        expect.objectContaining({ state: 'active', answered: true })
      );
      expect(client.context.client_call_id).not.toBe(id);
    }
  );

  it('does not label other incoming media failures as microphone denial', async () => {
    await connect();
    const incoming = new Inviter();
    client.incoming(incoming);
    incoming.accept.mockRejectedValue(new Error('SDP failed'));
    await expect(client.answer()).rejects.toThrow('answer_failed');
    expect(onCall).toHaveBeenLastCalledWith(
      expect.objectContaining({ state: 'failed', end_reason: 'answer_failed' })
    );
    expect(onError).not.toHaveBeenCalledWith('microphone_denied');
  });

  it('waits for actual Registered state and never initiates an INVITE during registration', async () => {
    const promise = client.connect(config);
    await vi.advanceTimersByTimeAsync(0);
    expect(onRegistration).not.toHaveBeenCalledWith('registered');
    Registerer.latest.stateChange.emit('Registered');
    await promise;
    expect(onRegistration).toHaveBeenLastCalledWith('registered');
    expect(client.session).toBeNull();
    expect(client.agent.options).toMatchObject({
      authorizationUsername: 'auth10',
      authorizationPassword: 'synthetic-password',
      logBuiltinEnabled: false,
      logConfiguration: false,
      reconnectionAttempts: 0,
    });
  });

  it('classifies final registration rejection without exposing credentials', async () => {
    const promise = client.connect(config);
    const assertion = expect(promise).rejects.toThrow('auth_error');
    await vi.advanceTimersByTimeAsync(0);
    Registerer.latest.register.mock.calls[0][0].requestDelegate.onReject({
      message: { statusCode: 403 },
    });
    await assertion;
    expect(onRegistration).toHaveBeenLastCalledWith('auth_error');
    expect(client.agent).toBeNull();
  });

  it('persists intent before dialing and refuses a second simultaneous call', async () => {
    await connect();
    await client.dial('0020');
    expect(onCall).toHaveBeenCalledWith(
      expect.objectContaining({
        direction: 'outgoing',
        remote_address: '0020',
        state: 'initiating',
      })
    );
    expect(Inviter.latest.invite).toHaveBeenCalledOnce();
    await expect(client.dial('0030')).rejects.toThrow('not_registered');
  });

  it('does not send INVITE when durable intent could not be created', async () => {
    await connect();
    onCall.mockRejectedValue(new Error('history_unavailable'));
    await expect(client.dial('0020')).rejects.toThrow();
    expect(Inviter.latest.invite).not.toHaveBeenCalled();
    expect(client.session).toBeNull();
  });

  it('receives and accepts a call only after explicit action', async () => {
    await connect();
    const invitation = new Inviter();
    client.agent.delegate.onInvite(invitation);
    expect(invitation.accept).not.toHaveBeenCalled();
    expect(invitation.progress).toHaveBeenCalledWith({ statusCode: 180 });
    expect(client.ringtone).not.toBeNull();
    expect(onCall).toHaveBeenCalledWith(
      expect.objectContaining({ direction: 'incoming', state: 'ringing' })
    );
    await client.answer();
    expect(client.ringtone).toBeNull();
    expect(invitation.accept).toHaveBeenCalledWith({
      sessionDescriptionHandlerOptions: {
        constraints: { audio: true, video: false },
      },
    });
  });

  it('distinguishes a call answered elsewhere from a missed call', async () => {
    await connect();
    const invitation = new Inviter();
    client.incoming(invitation);
    invitation.delegate.onCancel({
      request: {
        getHeader: () => 'SIP;cause=200;text="Call completed elsewhere"',
      },
    });
    invitation.stateChange.emit('Terminated');
    await vi.advanceTimersByTimeAsync(1);
    expect(onCall).toHaveBeenLastCalledWith(
      expect.objectContaining({ state: 'answered_elsewhere' })
    );
  });

  it('does not invent an answered duration or terminal outcome on network loss', async () => {
    await connect();
    await client.dial('0020');
    client.agent.delegate.onDisconnect(new Error('transport lost'));
    expect(onRegistration).toHaveBeenLastCalledWith('reconnecting');
    expect(onCall).toHaveBeenLastCalledWith(
      expect.objectContaining({
        state: 'awaiting_confirmation',
        answered: false,
      })
    );
    expect(Inviter.latest.invite).toHaveBeenCalledOnce();
  });

  it('rejects another invitation as busy without replacing the current session', async () => {
    await connect();
    await client.dial('0020');
    const active = client.session;
    const extra = new Inviter();
    client.incoming(extra);
    expect(extra.reject).toHaveBeenCalledWith({ statusCode: 486 });
    expect(client.session).toBe(active);
  });

  it('mutes only local audio and releases tracks on teardown', async () => {
    await connect();
    await client.dial('0020');
    const track = { kind: 'audio', enabled: true, stop: vi.fn() };
    client.session.sessionDescriptionHandler.peerConnection.getSenders = () => [
      { track },
    ];
    client.setMuted(true);
    expect(track.enabled).toBe(false);
    client.setMuted(false);
    expect(track.enabled).toBe(true);
    await client.disconnect();
    expect(track.stop).toHaveBeenCalled();
  });

  it('confirms transfer only after a successful final NOTIFY', async () => {
    await connect();
    await client.dial('0020');
    client.context.answered = true;
    const call = client.session;
    await client.transfer('0030');
    expect(onTransfer).toHaveBeenLastCalledWith('pending');
    call.refer.mock.calls[0][1].onNotify({
      request: { body: 'SIP/2.0 200 OK' },
      accept: vi.fn(),
    });
    expect(onTransfer).toHaveBeenLastCalledWith('completed');
  });

  it('sends only a valid DTMF digit for an established session', async () => {
    await connect();
    await client.dial('0020');
    client.context.answered = true;
    await client.dtmf('#');
    expect(client.session.info).toHaveBeenCalledWith({
      requestOptions: {
        body: {
          contentDisposition: 'render',
          contentType: 'application/dtmf-relay',
          content: 'Signal=#\r\nDuration=160',
        },
      },
    });
    await expect(client.dtmf('bad')).rejects.toThrow('dtmf_unavailable');
  });

  it.each([
    [486, 'busy'],
    [600, 'busy'],
    [603, 'rejected'],
    [480, 'unanswered'],
    [408, 'unanswered'],
    [503, 'failed'],
  ])(
    'maps SIP %i to %s without treating all failures as missed',
    (code, state) => expect(rejectedCallState(code)).toBe(state)
  );
});
