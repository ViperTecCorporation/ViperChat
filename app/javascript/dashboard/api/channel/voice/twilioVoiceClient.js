import { Device } from '@twilio/voice-sdk';
import VoiceAPI from './voiceAPIClient';

const createCallDisconnectedEvent = () => new CustomEvent('call:disconnected');

class TwilioVoiceClient extends EventTarget {
  constructor() {
    super();
    this.device = null;
    this.activeConnection = null;
    this.initialized = false;
    this.inboxId = null;
  }

  async initializeDevice(inboxId) {
    this.destroyDevice();

    // eslint-disable-next-line no-console
    console.log('[TwilioVoiceClient] initializeDevice', { inboxId });
    const response = await VoiceAPI.getToken(inboxId);
    const { token, account_id } = response || {};
    if (!token) throw new Error('Invalid token');

    this.device = new Device(token, {
      allowIncomingWhileBusy: true,
      disableAudioContextSounds: true,
      appParams: { account_id },
    });

    this.device.removeAllListeners();
    this.device.on('connect', conn => {
      this.activeConnection = conn;
      // eslint-disable-next-line no-console
      console.log('[TwilioVoiceClient] connected', { inboxId });
      conn.on('disconnect', this.onDisconnect);
    });

    this.device.on('disconnect', this.onDisconnect);

    this.device.on('tokenWillExpire', async () => {
      // eslint-disable-next-line no-console
      console.log('[TwilioVoiceClient] tokenWillExpire', {
        inboxId: this.inboxId,
      });
      const r = await VoiceAPI.getToken(this.inboxId);
      if (r?.token) this.device.updateToken(r.token);
    });

    this.initialized = true;
    this.inboxId = inboxId;

    // eslint-disable-next-line no-console
    console.log('[TwilioVoiceClient] deviceReady', {
      inboxId,
      accountId: account_id,
    });
    return this.device;
  }

  get hasActiveConnection() {
    return !!this.activeConnection;
  }

  endClientCall() {
    // eslint-disable-next-line no-console
    console.log('[TwilioVoiceClient] endClientCall', { inboxId: this.inboxId });
    if (this.activeConnection) {
      this.activeConnection.disconnect();
    }
    this.activeConnection = null;
    if (this.device) {
      this.device.disconnectAll();
    }
  }

  destroyDevice() {
    // eslint-disable-next-line no-console
    console.log('[TwilioVoiceClient] destroyDevice', { inboxId: this.inboxId });
    if (this.device) {
      this.device.destroy();
    }
    this.activeConnection = null;
    this.device = null;
    this.initialized = false;
    this.inboxId = null;
  }

  async joinClientCall({ to, conversationId }) {
    if (!this.device || !this.initialized || !to) return null;
    if (this.activeConnection) return this.activeConnection;

    const params = {
      To: to,
      is_agent: 'true',
      conversation_id: conversationId,
    };

    // eslint-disable-next-line no-console
    console.log('[TwilioVoiceClient] joinClientCall', {
      inboxId: this.inboxId,
      conversationId,
      to,
    });
    const connection = await this.device.connect({ params });
    this.activeConnection = connection;

    connection.on('disconnect', this.onDisconnect);

    return connection;
  }

  sendDtmf(digits) {
    if (!digits || !this.activeConnection) return false;
    if (typeof this.activeConnection.sendDigits !== 'function') return false;

    // eslint-disable-next-line no-console
    console.log('[TwilioVoiceClient] sendDtmf', {
      inboxId: this.inboxId,
      digits,
    });
    this.activeConnection.sendDigits(digits.toString());
    return true;
  }

  onDisconnect = () => {
    // eslint-disable-next-line no-console
    console.log('[TwilioVoiceClient] disconnected', { inboxId: this.inboxId });
    this.activeConnection = null;
    this.dispatchEvent(createCallDisconnectedEvent());
  };
}

export default new TwilioVoiceClient();
