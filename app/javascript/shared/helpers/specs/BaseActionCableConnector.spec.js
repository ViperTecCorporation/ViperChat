import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import BaseActionCableConnector from '../BaseActionCableConnector';

const actionCableMocks = vi.hoisted(() => ({
  createConsumer: vi.fn(),
}));

vi.mock('@rails/actioncable', () => ({
  createConsumer: actionCableMocks.createConsumer,
}));

describe('BaseActionCableConnector', () => {
  let app;
  let callbacks;
  let consumer;
  let connector;
  let subscription;

  beforeEach(() => {
    vi.useFakeTimers();

    app = {
      $store: {
        getters: {
          getCurrentAccountId: 16,
          getCurrentUserID: 86,
        },
      },
    };
    subscription = {
      updatePresence: vi.fn(),
    };
    consumer = {
      connection: {
        isOpen: vi.fn(() => true),
      },
      subscriptions: {
        create: vi.fn((identifier, handlers) => {
          callbacks = handlers;
          return subscription;
        }),
        sendCommand: vi.fn(),
      },
      disconnect: vi.fn(),
    };
    actionCableMocks.createConsumer.mockReturnValue(consumer);

    connector = new BaseActionCableConnector(app, 'pubsub-token');
  });

  afterEach(() => {
    connector.disconnect();
    BaseActionCableConnector.isDisconnected = false;
    vi.clearAllMocks();
    vi.clearAllTimers();
    vi.useRealTimers();
  });

  it('retries a RoomChannel subscription that was not confirmed', () => {
    vi.advanceTimersByTime(2999);
    expect(consumer.subscriptions.sendCommand).not.toHaveBeenCalled();

    vi.advanceTimersByTime(1);
    expect(consumer.subscriptions.sendCommand).toHaveBeenCalledOnce();
    expect(consumer.subscriptions.sendCommand).toHaveBeenCalledWith(
      subscription,
      'subscribe'
    );

    vi.advanceTimersByTime(3000);
    expect(consumer.subscriptions.sendCommand).toHaveBeenCalledTimes(2);
  });

  it('stops retrying after the server confirms the subscription', () => {
    vi.advanceTimersByTime(3000);
    callbacks.connected();

    vi.advanceTimersByTime(9000);
    expect(consumer.subscriptions.sendCommand).toHaveBeenCalledOnce();
  });

  it('waits for an open socket before retrying the subscription', () => {
    consumer.connection.isOpen.mockReturnValue(false);
    vi.advanceTimersByTime(3000);
    expect(consumer.subscriptions.sendCommand).not.toHaveBeenCalled();

    consumer.connection.isOpen.mockReturnValue(true);
    vi.advanceTimersByTime(3000);
    expect(consumer.subscriptions.sendCommand).toHaveBeenCalledOnce();
  });

  it('does not retry a subscription rejected by the server', () => {
    callbacks.rejected();

    vi.advanceTimersByTime(9000);
    expect(consumer.subscriptions.sendCommand).not.toHaveBeenCalled();
  });

  it('refreshes REST-backed state only after a reconnected channel is confirmed', () => {
    connector.onDisconnected = vi.fn();
    connector.onReconnect = vi.fn();

    callbacks.disconnected();
    vi.advanceTimersByTime(1000);

    expect(connector.onDisconnected).toHaveBeenCalledOnce();
    expect(connector.onReconnect).not.toHaveBeenCalled();

    callbacks.connected();
    expect(connector.onReconnect).toHaveBeenCalledOnce();
  });

  it('clears retry and presence timers when manually disconnected', () => {
    connector.disconnect();

    vi.advanceTimersByTime(60000);
    expect(consumer.subscriptions.sendCommand).not.toHaveBeenCalled();
    expect(subscription.updatePresence).not.toHaveBeenCalled();
    expect(consumer.disconnect).toHaveBeenCalledOnce();
  });
});
