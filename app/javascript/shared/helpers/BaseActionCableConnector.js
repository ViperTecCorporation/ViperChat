import { createConsumer } from '@rails/actioncable';

const PRESENCE_INTERVAL = 20000;
const RECONNECT_INTERVAL = 1000;
const SUBSCRIPTION_RETRY_INTERVAL = 3000;

class BaseActionCableConnector {
  static isDisconnected = false;

  constructor(
    app,
    pubsubToken,
    websocketHost = '',
    presenceInterval = PRESENCE_INTERVAL
  ) {
    const websocketURL = websocketHost ? `${websocketHost}/cable` : undefined;

    this.app = app;
    this.events = {};
    this.reconnectTimer = null;
    this.presenceTimer = null;
    this.subscriptionRetryTimer = null;
    this.isSubscriptionConfirmed = false;
    this.isSubscriptionRejected = false;
    this.isManuallyDisconnected = false;
    this.isAValidEvent = () => true;

    this.consumer = createConsumer(websocketURL);
    this.subscription = this.consumer.subscriptions.create(
      {
        channel: 'RoomChannel',
        pubsub_token: pubsubToken,
        account_id: app.$store.getters.getCurrentAccountId,
        user_id: app.$store.getters.getCurrentUserID,
      },
      {
        connected: () => {
          if (this.isManuallyDisconnected) return;

          const shouldHandleReconnect = BaseActionCableConnector.isDisconnected;
          this.isSubscriptionConfirmed = true;
          this.clearSubscriptionRetryTimer();
          this.clearReconnectTimer();
          BaseActionCableConnector.isDisconnected = false;
          if (shouldHandleReconnect) {
            this.onReconnect();
          }
        },
        updatePresence() {
          this.perform('update_presence');
        },
        received: this.onReceived,
        disconnected: () => {
          this.isSubscriptionConfirmed = false;
          if (this.isManuallyDisconnected) return;

          BaseActionCableConnector.isDisconnected = true;
          this.onDisconnected();
          this.initReconnectTimer();
          this.initSubscriptionRetryTimer();
        },
        rejected: () => {
          this.isSubscriptionConfirmed = false;
          this.isSubscriptionRejected = true;
          this.clearSubscriptionRetryTimer();
        },
      }
    );
    this.initSubscriptionRetryTimer();
    this.triggerPresenceInterval = () => {
      this.presenceTimer = setTimeout(() => {
        this.subscription.updatePresence();
        this.triggerPresenceInterval();
      }, presenceInterval);
    };
    this.triggerPresenceInterval();
  }

  checkConnection() {
    if (this.isManuallyDisconnected) {
      return;
    }

    const isConnectionActive = this.consumer.connection.isOpen();
    if (isConnectionActive) {
      this.clearReconnectTimer();
    } else {
      this.initReconnectTimer();
    }
  }

  clearReconnectTimer = () => {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  };

  initReconnectTimer = () => {
    if (this.isManuallyDisconnected) {
      return;
    }

    this.clearReconnectTimer();
    this.reconnectTimer = setTimeout(() => {
      this.checkConnection();
    }, RECONNECT_INTERVAL);
  };

  clearSubscriptionRetryTimer = () => {
    if (this.subscriptionRetryTimer) {
      clearTimeout(this.subscriptionRetryTimer);
      this.subscriptionRetryTimer = null;
    }
  };

  initSubscriptionRetryTimer = () => {
    if (
      this.isManuallyDisconnected ||
      this.isSubscriptionConfirmed ||
      this.isSubscriptionRejected
    ) {
      return;
    }

    this.clearSubscriptionRetryTimer();
    this.subscriptionRetryTimer = setTimeout(() => {
      this.subscriptionRetryTimer = null;

      if (this.consumer.connection.isOpen()) {
        this.consumer.subscriptions.sendCommand(this.subscription, 'subscribe');
      }

      this.initSubscriptionRetryTimer();
    }, SUBSCRIPTION_RETRY_INTERVAL);
  };

  clearPresenceTimer = () => {
    if (this.presenceTimer) {
      clearTimeout(this.presenceTimer);
      this.presenceTimer = null;
    }
  };

  // eslint-disable-next-line class-methods-use-this
  onReconnect = () => {};

  // eslint-disable-next-line class-methods-use-this
  onDisconnected = () => {};

  disconnect() {
    this.isManuallyDisconnected = true;
    this.clearReconnectTimer();
    this.clearSubscriptionRetryTimer();
    this.clearPresenceTimer();
    this.consumer.disconnect();
  }

  onReceived = ({ event, data } = {}) => {
    if (this.isAValidEvent(data)) {
      if (this.events[event] && typeof this.events[event] === 'function') {
        this.events[event](data);
      }
    }
  };
}

export default BaseActionCableConnector;
