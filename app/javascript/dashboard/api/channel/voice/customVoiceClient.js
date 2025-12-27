import {
  UserAgent,
  Registerer,
  Inviter,
  SessionState,
} from 'sip.js';
import VoiceAPI from './voiceAPIClient';

const createCallDisconnectedEvent = () => new CustomEvent('call:disconnected');

class CustomVoiceClient extends EventTarget {
  constructor() {
    super();
    this.userAgent = null;
    this.registerer = null;
    this.activeSession = null;
    this.initialized = false;
    this.inboxId = null;
    this.webrtcConfig = null;
    this.token = null;
    this.authType = 'jwt';
  }

  async initializeDevice(inboxId) {
    if (this.initialized && this.inboxId === inboxId && this.userAgent) {
      // eslint-disable-next-line no-console
      console.log('[CustomVoiceClient] reuseDevice', { inboxId });
      return this.userAgent;
    }

    this.destroyDevice();

    // eslint-disable-next-line no-console
    console.log('[CustomVoiceClient] initializeDevice', { inboxId });
    const response = await VoiceAPI.getToken(inboxId);
    const { token, webrtc, provider, auth_type: authType, password } =
      response || {};
    if (provider !== 'custom') throw new Error('Invalid provider');
    if (!webrtc?.ws_url || !webrtc?.sip_domain) {
      throw new Error('Invalid WebRTC config');
    }

    const resolvedAuthType = authType || 'jwt';
    const credential =
      resolvedAuthType === 'password' ? password || token : token;

    if (resolvedAuthType === 'password' && !credential) {
      throw new Error('Missing WebRTC password');
    }

    if (resolvedAuthType === 'jwt' && !credential) {
      throw new Error('Invalid token');
    }

    const username = webrtc.username;
    if (!username) throw new Error('Missing WebRTC username');

    const uri = UserAgent.makeURI(`sip:${username}@${webrtc.sip_domain}`);
    if (!uri) throw new Error('Invalid SIP URI');

    // eslint-disable-next-line no-console
    console.log('[CustomVoiceClient] createUserAgent', {
      inboxId,
      wsUrl: webrtc.ws_url,
      sipDomain: webrtc.sip_domain,
      username,
      authType: resolvedAuthType,
      hasCredential: !!credential,
    });
    this.userAgent = new UserAgent({
      uri,
      authorizationUsername: username,
      authorizationPassword: credential || '',
      displayName: webrtc.display_name || username,
      transportOptions: { server: webrtc.ws_url },
    });

    await this.userAgent.start();
    this.registerer = new Registerer(this.userAgent);
    await this.registerer.register();

    this.webrtcConfig = webrtc;
    this.token = credential;
    this.authType = resolvedAuthType;
    this.initialized = true;
    this.inboxId = inboxId;

    // eslint-disable-next-line no-console
    console.log('[CustomVoiceClient] registered', { inboxId, username });
    return this.userAgent;
  }

  get hasActiveConnection() {
    return !!this.activeSession;
  }

  async joinClientCall({ to }) {
    if (!this.userAgent || !this.initialized || !to) return null;
    if (this.activeSession) return this.activeSession;

    const targetUri = this.buildTargetUri(to);
    // eslint-disable-next-line no-console
    console.log('[CustomVoiceClient] joinClientCall', {
      inboxId: this.inboxId,
      target: targetUri.toString?.() || targetUri,
    });
    const inviter = new Inviter(this.userAgent, targetUri, {
      extraHeaders: this.extraHeaders(),
    });

    this.activeSession = inviter;
    this.bindSession(inviter);

    await inviter.invite();

    return inviter;
  }

  endClientCall() {
    // eslint-disable-next-line no-console
    console.log('[CustomVoiceClient] endClientCall', { inboxId: this.inboxId });
    if (this.activeSession?.bye) {
      this.activeSession.bye();
    }
    this.activeSession = null;
    if (this.registerer) {
      this.registerer.unregister();
    }
  }

  destroyDevice() {
    // eslint-disable-next-line no-console
    console.log('[CustomVoiceClient] destroyDevice', { inboxId: this.inboxId });
    if (this.userAgent) {
      this.userAgent.stop();
    }
    this.activeSession = null;
    this.userAgent = null;
    this.registerer = null;
    this.webrtcConfig = null;
    this.token = null;
    this.authType = 'jwt';
    this.initialized = false;
    this.inboxId = null;
  }

  transferCall({ referTo }) {
    if (!this.activeSession || !referTo) return false;
    if (typeof this.activeSession.refer !== 'function') return false;

    const target = this.buildReferUri(referTo);
    // eslint-disable-next-line no-console
    console.log('[CustomVoiceClient] transferCall', {
      inboxId: this.inboxId,
      referTo: target.toString?.() || target,
    });
    this.activeSession.refer(target);
    return true;
  }

  bindSession(session) {
    session.stateChange.addListener(state => {
      // eslint-disable-next-line no-console
      console.log('[CustomVoiceClient] sessionState', {
        inboxId: this.inboxId,
        state,
      });
      if (state === SessionState.Terminated) {
        this.activeSession = null;
        this.dispatchEvent(createCallDisconnectedEvent());
      }
    });
  }

  buildTargetUri(target) {
    const value = target.toString().startsWith('sip:')
      ? target.toString()
      : `sip:${target}@${this.webrtcConfig.sip_domain}`;
    const uri = UserAgent.makeURI(value);
    if (!uri) throw new Error('Invalid target');
    return uri;
  }

  buildReferUri(referTo) {
    const value = referTo.toString().startsWith('sip:')
      ? referTo.toString()
      : `sip:${referTo}@${this.webrtcConfig.sip_domain}`;
    const uri = UserAgent.makeURI(value);
    if (!uri) throw new Error('Invalid refer target');
    return uri;
  }

  extraHeaders() {
    if (this.authType !== 'jwt' || !this.token) return [];
    return [`Authorization: Bearer ${this.token}`];
  }
}

export default new CustomVoiceClient();
