import { defineStore } from 'pinia';
import { VoipAPI } from 'dashboard/api/voip';
import { AgentSipClient } from 'dashboard/lib/voip/AgentSipClient';

let runtime;
let api;
let releaseLock;
let reconnectTimer;
let heartbeatTimer;
let generation = 0;
let retry = 0;
let connectedRevision = '';
const observations = new Map();

export const useAgentVoipStore = defineStore('agentVoip', {
  state: () => ({
    accountId: null,
    accountUserId: null,
    services: [],
    bindings: [],
    registration: 'disconnected',
    call: null,
    expanded: true,
    muted: false,
    error: '',
    transferState: '',
    historyVersion: 0,
    historyPending: false,
    dialer: { open: false, address: '', serviceId: null, kind: 'manual' },
  }),
  getters: {
    activeBinding: state =>
      state.bindings.find(binding => binding.active) || null,
    activeService() {
      return (
        this.services.find(
          service => service.id === this.activeBinding?.voip_service_id
        ) || null
      );
    },
    connected: state => state.registration === 'registered',
  },
  actions: {
    openDialer({ address = '', serviceId = null, kind = 'manual' } = {}) {
      this.dialer = {
        open: true,
        address,
        serviceId: serviceId || this.activeService?.id || null,
        kind,
      };
    },
    closeDialer() {
      this.dialer = {
        open: false,
        address: '',
        serviceId: null,
        kind: 'manual',
      };
    },
    async prepare(accountId) {
      if (Number(accountId) === this.accountId) return;
      await this.stop();
      this.accountId = Number(accountId);
      api = new VoipAPI(accountId);
      await this.reloadProfile();
      if (this.activeBinding && this.activeService)
        await this.connect().catch(() => {});
    },
    async reloadProfile() {
      const original = api;
      const { data } = await original.profile();
      if (original !== api) return;
      this.services = data.services;
      this.bindings = data.bindings;
      this.accountUserId = data.account_user_id;
    },
    async claimTab() {
      if (releaseLock) return true;
      if (!navigator.locks) {
        this.registration = 'coordination_unavailable';
        return false;
      }
      return new Promise(resolve => {
        navigator.locks
          .request(
            `voip:${this.accountId}:${this.accountUserId}`,
            { ifAvailable: true },
            lock => {
              if (!lock) {
                this.registration = 'other_tab';
                resolve(false);
                return undefined;
              }
              return new Promise(release => {
                releaseLock = release;
                resolve(true);
              });
            }
          )
          .catch(() => {
            this.registration = 'coordination_unavailable';
            resolve(false);
          });
      });
    },
    async connect(bindingId, { registrationOnly = false } = {}) {
      if (this.call) throw new Error('voip_call_in_progress');
      if (!(await this.claimTab())) throw new Error('other_tab');
      clearTimeout(reconnectTimer);
      generation += 1;
      const currentGeneration = generation;
      const original = api;
      try {
        const { data } = await original.bootstrap(bindingId);
        if (currentGeneration !== generation || original !== api) return;
        await runtime?.disconnect();
        const client = new AgentSipClient({
          onRegistration: status => {
            if (currentGeneration !== generation) return;
            this.registration = status;
            if (status === 'registered') {
              retry = 0;
              this.error = '';
            }
            if (status === 'reconnecting') this.scheduleReconnect();
          },
          onCall: value =>
            this.recordObservation(
              value,
              data.binding_id,
              original,
              currentGeneration
            ),
          onError: code => {
            if (currentGeneration !== generation) return;
            this.error = code;
          },
          onTransfer: state => {
            if (currentGeneration !== generation) return;
            this.transferState = state;
          },
        });
        runtime = client;
        await client.connect(data, { registrationOnly });
        if (currentGeneration !== generation) {
          await client.disconnect();
          return;
        }
        connectedRevision = this.configurationRevision();
        clearInterval(heartbeatTimer);
        heartbeatTimer = setInterval(() => {
          if (this.call && runtime?.context)
            runtime.report(this.call.state).catch(() => {});
          this.flushObservations();
        }, 20000);
      } catch (error) {
        if (currentGeneration !== generation) return;
        this.error = 'registration_failed';
        if (this.registration !== 'auth_error') this.scheduleReconnect();
        throw error;
      }
    },
    scheduleReconnect() {
      clearTimeout(reconnectTimer);
      if (!this.activeBinding || !this.activeService || this.call) return;
      const delay = Math.min(1000 * 2 ** retry, 30000);
      retry += 1;
      reconnectTimer = setTimeout(() => this.connect().catch(() => {}), delay);
    },
    async testBinding(bindingId) {
      if (this.call) throw new Error('voip_call_in_progress');
      clearTimeout(reconnectTimer);
      try {
        await this.connect(bindingId, { registrationOnly: true });
      } finally {
        await this.stopConnection();
        if (this.activeBinding && this.activeService)
          await this.connect().catch(() => {});
      }
    },
    async activate(bindingId) {
      if (this.call) throw new Error('voip_call_in_progress');
      const original = api;
      await original.activate(bindingId);
      if (original !== api) return;
      await this.stopConnection();
      if (original !== api) return;
      await this.reloadProfile();
      if (original !== api) return;
      if (bindingId) await this.connect();
    },
    configurationRevision() {
      return [
        this.activeBinding?.id,
        this.activeBinding?.updated_at,
        this.activeService?.updated_at,
      ].join(':');
    },
    async refreshConfiguration() {
      if (!api) return;
      try {
        await this.reloadProfile();
        if (this.call) return;
        if (!this.activeBinding || !this.activeService) {
          if (runtime) await this.stopConnection();
          return;
        }
        if (runtime && connectedRevision !== this.configurationRevision())
          await this.connect();
      } catch {
        this.error = 'configuration_unavailable';
      }
    },
    async recordObservation(
      value,
      bindingId,
      original,
      ownerGeneration = generation
    ) {
      const key = `${original.accountId}:${value.client_call_id}`;
      let pending = observations.get(key);
      if (!pending) {
        if (ownerGeneration === generation) {
          this.error = '';
          this.transferState = '';
          this.muted = false;
        }
        const call = {
          client_call_id: value.client_call_id,
          sip_call_id: value.sip_call_id,
          direction: value.direction,
          remote_address: value.remote_address,
        };
        pending = {
          key,
          api: original,
          ownerGeneration,
          bindingId,
          call,
          row: null,
          sequence: 0,
          queue: [],
          running: null,
        };
        observations.set(key, pending);
      }
      pending.sequence += 1;
      pending.queue.push({
        event_id: crypto.randomUUID(),
        sequence: pending.sequence,
        state: value.state,
        sip_code: value.sip_code,
        end_reason: value.end_reason,
      });
      const terminal = ![
        'initiating',
        'ringing',
        'active',
        'awaiting_confirmation',
      ].includes(value.state);
      pending.terminal = terminal || value.finished;
      if (ownerGeneration !== generation) {
        await this.flushOne(pending);
        return;
      }
      this.call =
        terminal || value.finished
          ? null
          : {
              ...pending.call,
              remote_identity: pending.row?.remote_identity || null,
              state: value.state,
              answeredAt:
                (this.call?.client_call_id === value.client_call_id &&
                  this.call.answeredAt) ||
                (value.state === 'active' ? Date.now() : null),
            };
      if (terminal) {
        this.muted = false;
      }
      await this.flushOne(pending);
    },
    async flushOne(pending) {
      if (pending.running) return pending.running;
      pending.running = (async () => {
        try {
          if (!pending.row) {
            pending.row = (
              await pending.api.createCall(pending.bindingId, pending.call)
            ).data;
            if (
              pending.api === api &&
              pending.ownerGeneration === generation &&
              this.call?.client_call_id === pending.call.client_call_id
            ) {
              this.call.remote_identity = pending.row.remote_identity || null;
            }
          }
          await this.flushQueue(pending);
          if (pending.terminal) {
            observations.delete(pending.key);
            if (pending.api === api) this.historyVersion += 1;
          }
          this.historyPending = [...observations.values()].some(
            item => item.queue.length > 0
          );
        } catch (error) {
          this.historyPending = true;
          this.error = 'history_unavailable';
          throw new Error('history_unavailable');
        } finally {
          pending.running = null;
        }
      })();
      return pending.running;
    },
    async flushQueue(pending) {
      if (!pending.queue.length) return;
      await pending.api.observe(pending.row.id, pending.queue[0]);
      pending.queue.shift();
      await this.flushQueue(pending);
    },
    flushObservations() {
      observations.forEach(pending => {
        if (pending.queue.length) this.flushOne(pending).catch(() => {});
      });
    },
    async dial(address) {
      if (this.call || !this.connected) throw new Error('not_registered');
      await runtime.dial(address.trim());
    },
    async answer() {
      await runtime?.answer();
    },
    async hangup() {
      await runtime?.end();
    },
    toggleMute() {
      this.muted = !this.muted;
      runtime?.setMuted(this.muted);
    },
    async dtmf(digit) {
      await runtime?.dtmf(digit);
    },
    async transfer(address) {
      await runtime?.transfer(address);
    },
    async microphone(id) {
      await runtime?.microphone(id);
    },
    async speaker(id) {
      await runtime?.speaker(id);
    },
    async resumeAudio() {
      await runtime?.resumeAudio();
    },
    async stopConnection() {
      generation += 1;
      clearTimeout(reconnectTimer);
      clearInterval(heartbeatTimer);
      await runtime?.disconnect();
      runtime = null;
      connectedRevision = '';
      this.registration = 'disconnected';
      this.call = null;
      if (releaseLock) {
        releaseLock();
        releaseLock = null;
      }
    },
    async stop() {
      await this.stopConnection();
      observations.clear();
      this.$reset();
      api = null;
    },
  },
});
