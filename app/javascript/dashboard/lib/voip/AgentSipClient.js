import {
  UserAgent,
  Registerer,
  RegistererState,
  Inviter,
  SessionState,
  Grammar,
} from 'sip.js';
import incomingTone from 'dashboard/assets/audio/ring.mp3';
import outgoingTone from 'dashboard/assets/audio/calling.mp3';

export const rejectedCallState = code => {
  if (code === 486 || code === 600) return 'busy';
  if (code === 603) return 'rejected';
  if (code === 480 || code === 408) return 'unanswered';
  return 'failed';
};

// Independent from inboxes and conversations. Credentials live only inside SIP.js.
export class AgentSipClient {
  constructor({
    onRegistration,
    onCall,
    onError,
    onTransfer,
    onAudioReady = () => {},
  }) {
    Object.assign(this, {
      onRegistration,
      onCall,
      onError,
      onTransfer,
      onAudioReady,
    });
    this.session = null;
    this.agent = null;
    this.registerer = null;
    this.audio = null;
    this.ringtone = null;
    this.microphoneId = '';
    this.muted = false;
    this.stopping = false;
  }

  async connect(config, { registrationOnly = false } = {}) {
    if (this.session) throw new Error('voip_call_in_progress');
    await this.disconnect();
    this.stopping = false;
    this.registrationOnly = registrationOnly;
    this.domain = config.sip_domain;
    this.canTransfer = config.transfer_enabled;
    this.audio = document.createElement('audio');
    this.audio.autoplay = true;
    this.toneAudio = document.createElement('audio');
    this.toneAudio.src = incomingTone;
    this.toneAudio.preload = 'auto';
    this.toneUnlocked = false;
    this.audioInteraction = () => {
      if (this.ringtone) {
        if (this.audioBlocked) this.resumeAudio();
        return;
      }
      if (this.toneUnlocked) return;
      const tone = this.toneAudio;
      tone.muted = true;
      tone
        .play()
        .then(() => {
          if (this.toneAudio !== tone) return;
          this.toneUnlocked = true;
          if (this.ringtone !== tone) {
            tone.pause();
            tone.currentTime = 0;
          }
          tone.muted = false;
        })
        .catch(() => {
          tone.muted = false;
        });
    };
    window.addEventListener('pointerdown', this.audioInteraction);
    window.addEventListener('keydown', this.audioInteraction);
    this.onRegistration('connecting');
    this.agent = new UserAgent({
      uri: UserAgent.makeURI(`sip:${config.extension}@${config.sip_domain}`),
      authorizationUsername: config.username,
      authorizationPassword: config.password,
      displayName: config.extension,
      logBuiltinEnabled: false,
      logConfiguration: false,
      reconnectionAttempts: 0,
      transportOptions: {
        server: config.wss_url,
        traceSip: false,
        connectionTimeout: 10,
      },
      sessionDescriptionHandlerFactoryOptions: {
        peerConnectionConfiguration: { iceServers: config.ice_servers || [] },
      },
      delegate: {
        onInvite: invitation => this.incoming(invitation),
        onDisconnect: () => {
          if (this.stopping) return;
          this.onRegistration('reconnecting');
          if (this.context) this.report('awaiting_confirmation');
        },
      },
    });
    try {
      await this.agent.start();
      this.registerer = new Registerer(this.agent, {
        expires: config.registration_expires,
        logConfiguration: false,
      });
      const registerer = this.registerer;
      registerer.stateChange.addListener(state => {
        if (this.stopping || this.registerer !== registerer) return;
        if (state === RegistererState.Registered)
          this.onRegistration('registered');
        if (
          state === RegistererState.Unregistered ||
          state === RegistererState.Terminated
        )
          this.onRegistration('reconnecting', registerer.retryAfter);
      });
      await this.waitForRegistration();
    } catch (error) {
      const state =
        error.message === 'auth_error' ? 'auth_error' : 'unavailable';
      await this.disconnect();
      this.onRegistration(state);
      throw new Error(state);
    }
  }

  waitForRegistration() {
    return new Promise((resolve, reject) => {
      let settled = false;
      let timeout;
      let listener;
      const finish = error => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        this.registerer?.stateChange.removeListener(listener);
        if (error) reject(error);
        else resolve();
      };
      listener = state => {
        if (state === RegistererState.Registered) {
          finish();
        }
      };
      timeout = setTimeout(
        () => finish(new Error('registration_timeout')),
        15000
      );
      this.registerer.stateChange.addListener(listener);
      this.registerer
        .register({
          requestDelegate: {
            onAccept: () => {
              this.onRegistration('registered');
              finish();
            },
            onReject: response => {
              const code = response.message.statusCode;
              finish(
                new Error(
                  [401, 403, 407].includes(code) ? 'auth_error' : 'unavailable'
                )
              );
            },
          },
        })
        .catch(() => finish(new Error('unavailable')));
    });
  }

  async recoverRegistration() {
    if (this.stopping || !this.agent || !this.registerer) return;
    // Keep the existing dialog and media while recovering WSS/REGISTER.
    await this.agent.reconnect();
    await this.waitForRegistration();
  }

  constraints() {
    return {
      constraints: {
        audio: this.microphoneId
          ? { deviceId: { exact: this.microphoneId } }
          : true,
        video: false,
      },
    };
  }

  async dial(address) {
    if (
      this.session ||
      !this.agent ||
      this.registerer?.state !== RegistererState.Registered
    )
      throw new Error('not_registered');
    if (!/^[a-zA-Z0-9_.+*#-]{1,128}$/.test(address))
      throw new Error('invalid_destination');
    const target = UserAgent.makeURI(`sip:${address}@${this.domain}`);
    const session = new Inviter(this.agent, target, {
      sessionDescriptionHandlerOptions: this.constraints(),
    });
    this.track(session, 'outgoing', address);
    try {
      await this.report('initiating');
      const invitation = session.invite({
        requestDelegate: {
          onProgress: response => {
            if (this.session !== session) return;
            this.confirmRemoteAddress(response.message);
            this.report('ringing').catch(() =>
              this.onError('history_unavailable')
            );
            if (response.message.statusCode === 180) this.startRingtone(false);
          },
          onAccept: response => {
            if (this.session !== session) return;
            this.stopRingtone();
            this.confirmRemoteAddress(response.message);
            this.report('active').catch(() =>
              this.onError('history_unavailable')
            );
          },
          onReject: response => {
            if (this.session !== session || !this.context) return;
            this.stopRingtone();
            this.context.outcome = rejectedCallState(
              response.message.statusCode
            );
            this.context.sip_code = response.message.statusCode;
          },
        },
      });
      if (this.session === session && !this.context?.answered)
        this.startRingtone(false);
      await invitation;
    } catch (error) {
      this.context.outcome = 'failed';
      this.context.end_reason =
        error.name === 'NotAllowedError'
          ? 'microphone_denied'
          : 'invite_failed';
      await this.finish();
      throw new Error('invite_failed');
    }
  }

  incoming(session) {
    if (this.session || this.stopping || this.registrationOnly) {
      session.reject({ statusCode: 486 });
      return;
    }
    this.track(
      session,
      'incoming',
      session.remoteIdentity.uri.user || 'unknown'
    );
    this.report('ringing').catch(() => this.onError('history_unavailable'));
    session
      .progress({ statusCode: 180 })
      .catch(() => this.onError('signaling_failed'));
    this.startRingtone(true);
  }

  confirmRemoteAddress(message) {
    // Only the connected SIP service can expand a local dial string; never guess a DDD.
    const asserted = message.getHeader?.('P-Asserted-Identity');
    const identity = asserted ? Grammar.nameAddrHeaderParse(asserted) : null;
    const address = identity?.uri?.user || message.to?.uri?.user;
    if (/^\+?\d{10,15}$/.test(address || '')) {
      this.context.resolved_address = address;
    }
  }

  track(session, direction, address) {
    this.session = session;
    this.muted = false;
    this.context = {
      client_call_id: crypto.randomUUID(),
      sip_call_id: session.request?.callId,
      direction,
      remote_address: address,
      outcome: null,
      answered: false,
      finished: false,
    };
    session.delegate = {
      onBye: () => {
        if (this.session !== session || !this.context) return;
        this.context.end_reason = 'remote_hangup';
      },
      onCancel: cancel => {
        const reason = cancel.request.getHeader('Reason') || '';
        this.context.outcome = /cause=200\b/.test(reason)
          ? 'answered_elsewhere'
          : 'missed';
        this.context.end_reason = 'remote_cancel';
      },
    };
    session.stateChange.addListener(state => {
      if (this.session !== session) return;
      if (state === SessionState.Established) {
        this.stopRingtone();
        this.context.answered = true;
        this.attachMedia();
        this.report('active').catch(() => this.onError('history_unavailable'));
      }
      if (state === SessionState.Terminated) {
        this.stopRingtone();
        // accept() can terminate before rejecting with the media permission error.
        if (this.answering === session) return;
        setTimeout(() => {
          if (this.session === session) {
            this.finish().catch(() => this.onError('history_unavailable'));
          }
        }, 0);
      }
    });
  }

  report(state) {
    if (!this.context) return Promise.resolve();
    return Promise.resolve(this.onCall({ ...this.context, state }));
  }

  async finish() {
    if (!this.context || this.context.finished) return;
    this.context.finished = true;
    const state =
      this.context.outcome ||
      (this.context.answered ? 'ended' : 'awaiting_confirmation');
    try {
      await this.report(state);
    } finally {
      this.releaseMedia();
      this.session = null;
      this.context = null;
    }
  }

  async answer() {
    if (
      !this.session ||
      this.context.direction !== 'incoming' ||
      this.context.answered
    )
      return;
    const session = this.session;
    if (this.answering === session) return;
    this.answering = session;
    try {
      this.stopRingtone();
      await session.accept({
        sessionDescriptionHandlerOptions: this.constraints(),
      });
    } catch (error) {
      const reason =
        error.name === 'NotAllowedError'
          ? 'microphone_denied'
          : 'answer_failed';
      if (this.session === session && this.context) {
        this.context.outcome = 'failed';
        this.context.end_reason = reason;
        try {
          if (session.state !== SessionState.Terminated) {
            await session.reject({ statusCode: 480 });
          }
        } finally {
          try {
            await this.finish();
          } finally {
            this.onError(reason);
          }
        }
      }
      throw new Error(reason);
    } finally {
      this.answering = null;
      if (
        this.session === session &&
        session.state === SessionState.Terminated
      ) {
        await this.finish();
      }
    }
  }

  async end() {
    if (!this.session || !this.context) return;
    this.stopRingtone();
    this.context.end_reason = 'local_hangup';
    if (this.session.state === SessionState.Established)
      await this.session.bye();
    else if (this.context.direction === 'incoming') {
      this.context.outcome = 'rejected';
      await this.session.reject({ statusCode: 603 });
    } else {
      this.context.outcome = 'cancelled';
      await this.session.cancel();
    }
  }

  attachMedia() {
    const pc = this.session?.sessionDescriptionHandler?.peerConnection;
    if (!pc) return;
    const stream = new MediaStream();
    pc.getReceivers().forEach(receiver => {
      if (receiver.track) stream.addTrack(receiver.track);
    });
    this.audio.srcObject = stream;
    this.resumeAudio();
    this.setMuted(this.muted);
  }

  async resumeAudio() {
    try {
      if (this.ringtone) await this.ringtone.play();
      if (this.audio?.srcObject) await this.audio.play();
      this.audioBlocked = false;
      this.onAudioReady();
    } catch {
      this.audioBlocked = true;
      this.onError('audio_blocked');
    }
  }

  setMuted(value) {
    this.muted = value;
    this.session?.sessionDescriptionHandler?.peerConnection
      ?.getSenders()
      .forEach(sender => {
        if (sender.track?.kind === 'audio') sender.track.enabled = !value;
      });
  }

  async microphone(deviceId) {
    this.microphoneId = deviceId;
    if (!this.session || !this.context?.answered) return;
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: deviceId ? { deviceId: { exact: deviceId } } : true,
      video: false,
    });
    const next = stream.getAudioTracks()[0];
    next.enabled = !this.muted;
    const sender = this.session.sessionDescriptionHandler.peerConnection
      .getSenders()
      .find(item => item.track?.kind === 'audio');
    const previous = sender?.track;
    try {
      await sender.replaceTrack(next);
      previous?.stop();
    } catch (error) {
      next.stop();
      throw error;
    }
  }

  async speaker(deviceId) {
    if (!this.audio?.setSinkId) throw new Error('output_unsupported');
    await this.audio.setSinkId(deviceId);
    await this.toneAudio?.setSinkId(deviceId);
  }

  async dtmf(digit) {
    if (!/^[0-9*#]$/.test(digit) || !this.context?.answered)
      throw new Error('dtmf_unavailable');
    const sdh = this.session.sessionDescriptionHandler;
    if (sdh?.sendDtmf?.(digit)) return;
    await this.session.info({
      requestOptions: {
        body: {
          contentDisposition: 'render',
          contentType: 'application/dtmf-relay',
          content: `Signal=${digit}\r\nDuration=160`,
        },
      },
    });
  }

  async transfer(address) {
    if (
      !this.canTransfer ||
      !this.context?.answered ||
      !/^[a-zA-Z0-9_.+*-]{1,64}$/.test(address)
    )
      throw new Error('transfer_unavailable');
    const session = this.session;
    let completed = false;
    this.onTransfer('pending');
    try {
      await session.refer(UserAgent.makeURI(`sip:${address}@${this.domain}`), {
        requestDelegate: {
          onReject: () => {
            if (this.session === session) this.onTransfer('failed');
          },
        },
        onNotify: notification => {
          const match = (notification.request.body || '').match(
            /^SIP\/2.0\s+(\d{3})\b/m
          );
          notification.accept().catch(() => this.onError('signaling_failed'));
          if (this.session !== session || completed || !match) return;
          const code = Number(match[1]);
          if (code < 200) return;
          if (code >= 300) {
            this.onTransfer('failed');
            return;
          }
          completed = true;
          this.onTransfer('completed');
          this.context.end_reason = 'transferred';
          // A successful sipfrag, not REFER's 202, confirms the new leg.
          // Release only our dialog; do not wait forever for the peer's BYE.
          session.bye().catch(() => this.onError('signaling_failed'));
          this.finish().catch(() => this.onError('history_unavailable'));
        },
      });
    } catch (error) {
      if (this.session === session) this.onTransfer('failed');
      throw error;
    }
  }

  releaseMedia() {
    this.stopRingtone();
    this.session?.sessionDescriptionHandler?.peerConnection
      ?.getSenders()
      .forEach(sender => sender.track?.stop());
    if (this.audio) {
      this.audio.pause();
      this.audio.srcObject = null;
    }
  }

  startRingtone(incoming) {
    const src = incoming ? incomingTone : outgoingTone;
    if (this.ringtone && this.toneSource === src) return;
    this.stopRingtone();
    this.ringtone = this.toneAudio;
    this.toneSource = src;
    this.ringtone.src = src;
    this.ringtone.muted = false;
    this.ringtone.volume = 1;
    this.ringtone.loop = true;
    const tone = this.ringtone;
    tone
      .play()
      .then(() => {
        if (this.ringtone !== tone) return;
        this.audioBlocked = false;
        this.onAudioReady();
      })
      .catch(error => {
        if (this.ringtone !== tone || error.name === 'AbortError') return;
        this.audioBlocked = true;
        this.onError('audio_blocked');
      });
  }

  stopRingtone() {
    this.ringtone?.pause();
    if (this.ringtone) this.ringtone.currentTime = 0;
    this.ringtone = null;
    this.toneSource = null;
  }

  async disconnect() {
    this.stopping = true;
    window.removeEventListener('pointerdown', this.audioInteraction);
    window.removeEventListener('keydown', this.audioInteraction);
    if (this.session) await this.end().catch(() => {});
    await this.finish().catch(() => {});
    this.releaseMedia();
    await this.registerer?.unregister().catch(() => {});
    await this.agent?.stop().catch(() => {});
    this.registerer = null;
    this.agent = null;
    this.audio = null;
    this.toneAudio?.pause();
    this.toneAudio = null;
    this.context = null;
    this.session = null;
    this.onRegistration('disconnected');
  }
}
