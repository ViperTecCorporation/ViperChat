import { createPinia, setActivePinia } from 'pinia';
import { useAgentVoipStore } from '../agentVoip';
import { VoipAPI } from 'dashboard/api/voip';
import { AgentSipClient } from 'dashboard/lib/voip/AgentSipClient';

vi.mock('dashboard/api/voip', () => {
  class API {
    static instances = [];

    static emptyProfile = false;

    constructor(accountId) {
      this.accountId = accountId;
      API.instances.push(this);
    }

    profile = vi.fn().mockImplementation(async () => ({
      data: {
        services: [{ id: 1, updated_at: 'service-v1' }],
        bindings: API.emptyProfile
          ? []
          : [
              {
                id: 10,
                voip_service_id: 1,
                active: true,
                updated_at: 'binding-v1',
              },
            ],
        account_user_id: 50,
      },
    }));

    bootstrap = vi.fn().mockResolvedValue({
      data: { binding_id: 10, password: 'synthetic-only', extension: '0010' },
    });

    activate = vi.fn().mockResolvedValue({ data: {} });

    createCall = vi.fn().mockResolvedValue({ data: { id: 25 } });

    observe = vi.fn().mockResolvedValue({ data: {} });
  }
  return { VoipAPI: API };
});
vi.mock('dashboard/lib/voip/AgentSipClient', () => {
  const Client = vi.fn(function client(callbacks) {
    const instance = {
      callbacks,
      connect: vi
        .fn()
        .mockImplementation(async () => callbacks.onRegistration('registered')),
      disconnect: vi.fn().mockResolvedValue(),
      recoverRegistration: vi.fn().mockResolvedValue(),
      dial: vi.fn().mockResolvedValue(),
      report: vi.fn().mockResolvedValue(),
    };
    Client.instances.push(instance);
    return instance;
  });
  Client.instances = [];
  return { AgentSipClient: Client };
});

describe('agent VoIP coordination and persistence', () => {
  let phone;
  beforeEach(() => {
    vi.useFakeTimers();
    setActivePinia(createPinia());
    VoipAPI.instances = [];
    AgentSipClient.instances = [];
    VoipAPI.emptyProfile = false;
    Object.defineProperty(navigator, 'locks', {
      configurable: true,
      value: {
        request: vi.fn((name, options, callback) =>
          Promise.resolve(callback({ name }))
        ),
      },
    });
    phone = useAgentVoipStore();
  });
  afterEach(async () => {
    await phone.stop();
    vi.useRealTimers();
  });

  it('connects only the explicitly active binding and keeps secrets out of store state', async () => {
    await phone.prepare(1);
    expect(phone.registration).toBe('registered');
    expect(AgentSipClient.instances).toHaveLength(1);
    expect(JSON.stringify(phone.$state)).not.toContain('synthetic-only');
    expect(navigator.locks.request).toHaveBeenCalledWith(
      'voip:1:50',
      { ifAvailable: true },
      expect.any(Function)
    );
  });

  it('does not guess the first service when no binding is active', async () => {
    VoipAPI.emptyProfile = true;
    await phone.prepare(1);
    expect(phone.activeBinding).toBeNull();
    expect(phone.registration).toBe('disconnected');
    expect(AgentSipClient.instances).toHaveLength(0);
    expect(VoipAPI.instances[0].bootstrap).not.toHaveBeenCalled();
  });

  it('keeps audio blocking visible across registration refresh and clears only after audio plays', async () => {
    await phone.prepare(1);
    const callbacks = AgentSipClient.instances[0].callbacks;
    callbacks.onError('audio_blocked');
    callbacks.onRegistration('registered');
    expect(phone.error).toBe('audio_blocked');
    callbacks.onAudioReady();
    expect(phone.error).toBe('');
    callbacks.onError('microphone_denied');
    callbacks.onAudioReady();
    expect(phone.error).toBe('microphone_denied');
  });

  it('keeps retrying failed registrations without F5 and stops after registration succeeds', async () => {
    await phone.prepare(1);
    const api = VoipAPI.instances[0];
    api.bootstrap
      .mockRejectedValueOnce(new Error('offline'))
      .mockRejectedValueOnce(new Error('offline'));
    AgentSipClient.instances[0].callbacks.onRegistration('reconnecting');
    await vi.advanceTimersByTimeAsync(1000);
    await vi.advanceTimersByTimeAsync(2000);
    await vi.advanceTimersByTimeAsync(4000);
    expect(phone.connected).toBe(true);
    expect(api.bootstrap).toHaveBeenCalledTimes(4);
    await vi.advanceTimersByTimeAsync(60000);
    expect(api.bootstrap).toHaveBeenCalledTimes(4);
  });

  it('recovers signaling in-place during a live call and retries failures without tearing it down', async () => {
    await phone.prepare(1);
    const client = AgentSipClient.instances[0];
    phone.call = { state: 'active' };
    client.recoverRegistration.mockRejectedValue(new Error('offline'));
    client.callbacks.onRegistration('reconnecting');
    await vi.advanceTimersByTimeAsync(7000);
    expect(client.disconnect).not.toHaveBeenCalled();
    expect(client.recoverRegistration).toHaveBeenCalledTimes(3);
    phone.call = null;
    await vi.advanceTimersByTimeAsync(8000);
    expect(phone.connected).toBe(true);
    expect(VoipAPI.instances[0].bootstrap).toHaveBeenCalledTimes(2);
  });

  it('recovers a disconnected existing runtime on the periodic configuration refresh', async () => {
    await phone.prepare(1);
    AgentSipClient.instances[0].callbacks.onRegistration('disconnected');
    await phone.refreshConfiguration();
    expect(phone.connected).toBe(true);
    expect(VoipAPI.instances[0].bootstrap).toHaveBeenCalledTimes(2);
  });

  it('cancels retry on stop and does not duplicate simultaneous connection attempts', async () => {
    await phone.prepare(1);
    AgentSipClient.instances[0].callbacks.onRegistration('reconnecting');
    await phone.stop();
    await vi.advanceTimersByTimeAsync(60000);
    expect(AgentSipClient.instances).toHaveLength(1);
    await phone.prepare(1);
    const api = VoipAPI.instances.at(-1);
    await Promise.all([phone.connect(), phone.connect()]);
    expect(api.bootstrap).toHaveBeenCalledTimes(2);
  });

  it('automatically connects when the active extension becomes available after startup', async () => {
    VoipAPI.emptyProfile = true;
    await phone.prepare(1);
    VoipAPI.emptyProfile = false;
    await phone.refreshConfiguration();
    await phone.refreshConfiguration();
    expect(phone.registration).toBe('registered');
    expect(AgentSipClient.instances).toHaveLength(1);
    expect(VoipAPI.instances[0].bootstrap).toHaveBeenCalledTimes(1);
  });

  it('retries the profile automatically after a transient request failure', async () => {
    VoipAPI.emptyProfile = true;
    await phone.prepare(1);
    VoipAPI.instances[0].profile.mockRejectedValueOnce(new Error('network'));
    await phone.refreshConfiguration();
    VoipAPI.emptyProfile = false;
    await phone.refreshConfiguration();
    expect(phone.connected).toBe(true);
  });

  it('does not register if another tab owns the account/agent lock', async () => {
    navigator.locks.request.mockImplementation((name, options, callback) =>
      Promise.resolve(callback(null))
    );
    await phone.prepare(1);
    expect(phone.registration).toBe('other_tab');
    expect(AgentSipClient.instances).toHaveLength(0);
    expect(VoipAPI.instances[0].bootstrap).not.toHaveBeenCalled();
  });

  it('performs registration-only testing and restores the active binding afterwards', async () => {
    await phone.prepare(1);
    await phone.testBinding(11);
    expect(VoipAPI.instances[0].bootstrap).toHaveBeenCalledWith(11);
    expect(AgentSipClient.instances[1].connect).toHaveBeenCalledWith(
      expect.any(Object),
      { registrationOnly: true }
    );
    expect(AgentSipClient.instances[1].disconnect).toHaveBeenCalled();
    expect(phone.activeBinding.id).toBe(10);
    expect(
      AgentSipClient.instances.every(
        client => client.dial.mock.calls.length === 0
      )
    ).toBe(true);
  });

  it('blocks service switching while in a call', async () => {
    await phone.prepare(1);
    phone.call = { state: 'active' };
    await expect(phone.activate(11)).rejects.toThrow('voip_call_in_progress');
    expect(VoipAPI.instances[0].activate).not.toHaveBeenCalled();
  });

  it('persists the incoming permission failure on the same call and retains the alert after teardown', async () => {
    await phone.prepare(1);
    const { callbacks } = AgentSipClient.instances[0];
    const incoming = {
      client_call_id: 'denied-incoming',
      sip_call_id: 'same-sip-id',
      direction: 'incoming',
      remote_address: '1002',
      state: 'ringing',
    };
    await callbacks.onCall(incoming);
    await callbacks.onCall({
      ...incoming,
      state: 'failed',
      end_reason: 'microphone_denied',
      finished: true,
    });
    callbacks.onError('microphone_denied');
    expect(VoipAPI.instances[0].createCall).toHaveBeenCalledOnce();
    expect(VoipAPI.instances[0].observe).toHaveBeenLastCalledWith(
      25,
      expect.objectContaining({
        state: 'failed',
        end_reason: 'microphone_denied',
        sequence: 2,
      })
    );
    expect(phone.call).toBeNull();
    expect(phone.historyPending).toBe(false);
    expect(phone.error).toBe('microphone_denied');
    await callbacks.onCall({ ...incoming, client_call_id: 'new-incoming' });
    expect(phone.error).toBe('');
  });

  it('opens a dialer without activating services or starting a call and resets on account switch', async () => {
    await phone.prepare(1);
    phone.openDialer({
      address: '+55 (66) 99999-0000',
      serviceId: 2,
      kind: 'contacts',
    });
    expect(phone.dialer).toEqual({
      open: true,
      address: '+55 (66) 99999-0000',
      serviceId: 2,
      kind: 'contacts',
    });
    expect(VoipAPI.instances[0].activate).not.toHaveBeenCalled();
    expect(AgentSipClient.instances[0].dial).not.toHaveBeenCalled();
    await phone.prepare(2);
    expect(phone.dialer.open).toBe(false);
    expect(phone.dialer.address).toBe('');
  });

  it('keeps resolved identity across observations but never carries it into another call', async () => {
    await phone.prepare(1);
    const identity = {
      kind: 'agent',
      id: 7,
      name: 'Test agent',
      address: '0020',
      service_id: 1,
    };
    VoipAPI.instances[0].createCall.mockResolvedValueOnce({
      data: { id: 25, remote_identity: identity },
    });
    const callback = AgentSipClient.instances[0].callbacks.onCall;
    const value = {
      client_call_id: 'identity-call',
      remote_address: '0020',
      direction: 'incoming',
    };
    await callback({ ...value, state: 'ringing' });
    expect(phone.call.remote_identity).toEqual(identity);
    await callback({ ...value, state: 'active' });
    expect(phone.call.remote_identity).toEqual(identity);
    await callback({ ...value, state: 'ended', finished: true });
    await callback({
      ...value,
      client_call_id: 'another-call',
      remote_address: '0030',
      state: 'ringing',
    });
    expect(phone.call.remote_identity).toBeNull();
    expect(phone.call.answeredAt).toBeNull();
  });

  it('refreshes history only after a final observation is persisted, including a retry', async () => {
    await phone.prepare(1);
    const api = VoipAPI.instances[0];
    const callback = AgentSipClient.instances[0].callbacks.onCall;
    const value = {
      client_call_id: 'retry-final',
      sip_call_id: 'sip-final',
      direction: 'outgoing',
      remote_address: '0020',
    };
    await callback({ ...value, state: 'initiating' });
    api.observe.mockRejectedValueOnce(new Error('offline'));
    await expect(
      callback({ ...value, state: 'ended', finished: true })
    ).rejects.toThrow('history_unavailable');
    expect(phone.historyVersion).toBe(0);
    expect(phone.historyPending).toBe(true);
    expect(phone.call).toBeNull();
    phone.flushObservations();
    await vi.advanceTimersByTimeAsync(0);
    expect(phone.historyVersion).toBe(1);
    expect(phone.historyPending).toBe(false);
  });

  it('keeps a single canonical call with ordered observations and retries failed persistence', async () => {
    await phone.prepare(1);
    const api = VoipAPI.instances[0];
    api.observe.mockRejectedValueOnce(new Error('offline'));
    const callback = AgentSipClient.instances[0].callbacks.onCall;
    const value = {
      client_call_id: 'one-call',
      sip_call_id: 'sip-one',
      direction: 'outgoing',
      remote_address: '0020',
    };
    await expect(callback({ ...value, state: 'initiating' })).rejects.toThrow(
      'history_unavailable'
    );
    expect(phone.historyPending).toBe(true);
    await callback({ ...value, state: 'active' });
    expect(api.createCall).toHaveBeenCalledOnce();
    expect(api.observe.mock.calls.map(call => call[1].sequence)).toEqual([
      1, 1, 2,
    ]);
    await callback({ ...value, state: 'ended', finished: true });
    expect(phone.call).toBeNull();
    expect(phone.historyPending).toBe(false);
    expect(api.observe.mock.calls.at(-1)[1]).toMatchObject({
      sequence: 3,
      state: 'ended',
    });
  });

  it('tears down credentials and changes the captured API scope when switching accounts', async () => {
    await phone.prepare(1);
    const oldClient = AgentSipClient.instances[0];
    await phone.prepare(2);
    expect(oldClient.disconnect).toHaveBeenCalled();
    expect(phone.accountId).toBe(2);
    expect(VoipAPI.instances.map(instance => instance.accountId)).toEqual([
      1, 2,
    ]);
  });

  it('ignores an old service activation completing after the account changes', async () => {
    await phone.prepare(1);
    let finishActivation;
    VoipAPI.instances[0].activate.mockImplementation(
      () =>
        new Promise(resolve => {
          finishActivation = resolve;
        })
    );
    const activation = phone.activate(11);
    await phone.prepare(2);
    const currentClient = AgentSipClient.instances.at(-1);
    finishActivation({ data: {} });
    await activation;
    expect(currentClient.disconnect).not.toHaveBeenCalled();
    expect(phone.accountId).toBe(2);
    expect(phone.registration).toBe('registered');
  });

  it('ignores late registration, transfer and error callbacks from the previous account', async () => {
    await phone.prepare(1);
    const callbacks = AgentSipClient.instances[0].callbacks;
    await phone.prepare(2);
    callbacks.onRegistration('auth_error');
    callbacks.onError('old_account_error');
    callbacks.onTransfer('failed');
    expect(phone.registration).toBe('registered');
    expect(phone.error).toBe('');
    expect(phone.transferState).toBe('');
  });

  it('disconnects a disabled service only after the active call ends', async () => {
    await phone.prepare(1);
    const client = AgentSipClient.instances[0];
    phone.call = { state: 'active' };
    VoipAPI.instances[0].profile.mockResolvedValue({
      data: {
        services: [],
        bindings: [{ id: 10, voip_service_id: 1, active: true }],
        account_user_id: 50,
      },
    });
    await phone.refreshConfiguration();
    expect(client.disconnect).not.toHaveBeenCalled();
    phone.call = null;
    await phone.refreshConfiguration();
    expect(client.disconnect).toHaveBeenCalled();
    expect(phone.registration).toBe('disconnected');
  });
});
