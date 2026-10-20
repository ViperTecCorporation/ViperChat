import { describe, expect, it, vi } from 'vitest';
import ReplyBox from './ReplyBox.vue';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/composables', async importOriginal => ({
  ...(await importOriginal()),
  useAlert: vi.fn(),
}));

const createPixContext = (overrides = {}) => {
  const inboxes = {
    1: {
      id: 1,
      name: 'Uno payments',
      provider: 'unoapi',
      provider_config: { pix_key: 'uno@example.test', pix_key_type: 'EMAIL' },
    },
    2: {
      id: 2,
      name: 'Meta inbox',
      provider: 'whatsapp_cloud',
      provider_config: {
        pix_key: 'not-uno@example.test',
        pix_key_type: 'EMAIL',
      },
    },
  };
  const context = {
    selectedWhatsappProvider: 'whatsapp_cloud',
    whatsappTransportOptions: {
      link_id: 8,
      transports: [
        {
          provider: 'unoapi',
          label: 'ViperConnect',
          inbox_id: 1,
          can_reply: true,
          capabilities: { pix: true },
        },
        {
          provider: 'whatsapp_cloud',
          label: 'Meta',
          inbox_id: 2,
          can_reply: true,
          capabilities: { pix: false },
        },
      ],
    },
    currentChat: { id: 9, account_id: 4, inbox_id: 1 },
    inbox: inboxes[2],
    isAUnoapiChannel: false,
    isWebDestination: false,
    isOnPrivateNote: false,
    isComposerActive: true,
    deliveryDestination: 'channel',
    $store: {
      getters: { 'inboxes/getInbox': vi.fn(id => inboxes[id]) },
      dispatch: vi.fn().mockResolvedValue({}),
    },
    $refs: {
      pixPaymentConfirmDialog: {
        showConfirmation: vi.fn().mockResolvedValue(true),
      },
    },
    $t: (key, values = {}) => `${key} ${JSON.stringify(values)}`,
    removeFromDraft: vi.fn(),
    sendMessageAnalyticsData: vi.fn(),
    ...overrides,
  };
  [
    'pixPaymentResolution',
    'pixPaymentInbox',
    'showPixPaymentButton',
    'pixPaymentMessageContent',
    'pixPaymentConfirmationDescription',
  ].forEach(name => {
    Object.defineProperty(context, name, {
      get: () => ReplyBox.computed[name].call(context),
    });
  });
  context.sendMessage = ReplyBox.methods.sendMessage.bind(context);
  return context;
};

describe('PIX executor independent of WhatsApp preference', () => {
  it.each([
    ['unoapi', 'unoapi'],
    ['unoapi', 'whatsapp_cloud'],
    ['whatsapp_cloud', 'unoapi'],
    ['whatsapp_cloud', 'whatsapp_cloud'],
  ])(
    'uses the Uno configuration with primary=%s preferred=%s',
    async (primary, preferred) => {
      const context = createPixContext({ selectedWhatsappProvider: preferred });
      context.currentChat.inbox_id = primary === 'unoapi' ? 1 : 2;
      expect(context.showPixPaymentButton).toBe(true);
      expect(context.pixPaymentInbox.id).toBe(1);
      expect(context.pixPaymentMessageContent).toContain('uno@example.test');
      expect(context.pixPaymentMessageContent).not.toContain(
        'not-uno@example.test'
      );
      await ReplyBox.methods.sendPixPayment.call(context);
      expect(context.$store.dispatch).toHaveBeenCalledWith(
        'createPendingMessageAndSend',
        expect.objectContaining({
          conversationId: 9,
          whatsapp_transport: preferred,
          private: false,
          delivery_destination: 'channel',
          contentAttributes: {
            whatsapp_interactive: { type: 'payment_request' },
          },
        })
      );
      expect(context.selectedWhatsappProvider).toBe(preferred);
    }
  );

  it('discloses the actual executor and routing before the agent confirms', async () => {
    const context = createPixContext();
    context.$refs.pixPaymentConfirmDialog.showConfirmation.mockImplementation(
      async () => {
        expect(context.pixPaymentConfirmationDescription).toContain(
          'WHATSAPP_UNIFIED.WILL_ROUTE'
        );
        expect(context.pixPaymentConfirmationDescription).toContain(
          'ViperConnect'
        );
        expect(context.pixPaymentConfirmationDescription).toContain(
          'Uno payments'
        );
        expect(context.$store.dispatch).not.toHaveBeenCalled();
        return false;
      }
    );
    await ReplyBox.methods.sendPixPayment.call(context);
    expect(context.$store.dispatch).not.toHaveBeenCalled();
    expect(context.selectedWhatsappProvider).toBe('whatsapp_cloud');
  });

  it.each([
    'unknown',
    'unsupported',
    'unavailable',
    'missing configuration',
    'missing inbox',
  ])('does not offer or send PIX when executor is %s', async state => {
    const context = createPixContext();
    const uno = context.whatsappTransportOptions.transports[0];
    if (state === 'unknown') delete uno.capabilities.pix;
    if (state === 'unsupported') uno.capabilities.pix = false;
    if (state === 'unavailable') uno.can_reply = false;
    if (state === 'missing configuration')
      context.$store.getters['inboxes/getInbox'](1).provider_config = {};
    if (state === 'missing inbox')
      context.$store.getters['inboxes/getInbox'].mockReturnValue(undefined);
    expect(context.showPixPaymentButton).toBe(false);
    await ReplyBox.methods.sendPixPayment.call(context);
    expect(
      context.$refs.pixPaymentConfirmDialog.showConfirmation
    ).not.toHaveBeenCalled();
    expect(context.$store.dispatch).not.toHaveBeenCalled();
  });

  it.each(['web', 'note', 'group'])(
    'keeps PIX out of %s',
    async destination => {
      const context = createPixContext();
      if (destination === 'web') context.isWebDestination = true;
      if (destination === 'note') context.isOnPrivateNote = true;
      if (destination === 'group') context.currentChat.group = true;
      expect(context.showPixPaymentButton).toBe(false);
      await ReplyBox.methods.sendPixPayment.call(context);
      expect(context.$store.dispatch).not.toHaveBeenCalled();
    }
  );

  it.each([
    'preference',
    'executor',
    'configuration',
    'conversation',
    'link',
    'availability',
    'inactive composer',
  ])('requires a fresh confirmation after a change to %s', async change => {
    const context = createPixContext();
    let confirm;
    context.$refs.pixPaymentConfirmDialog.showConfirmation.mockImplementation(
      () =>
        new Promise(resolve => {
          confirm = resolve;
        })
    );
    const sending = ReplyBox.methods.sendPixPayment.call(context);
    if (change === 'preference') context.selectedWhatsappProvider = 'unoapi';
    if (change === 'executor')
      context.whatsappTransportOptions.transports[0].inbox_id = 3;
    if (change === 'configuration')
      context.$store.getters['inboxes/getInbox'](1).provider_config.pix_key =
        'changed@example.test';
    if (change === 'conversation') context.currentChat.id = 10;
    if (change === 'link') context.whatsappTransportOptions.link_id = 12;
    if (change === 'availability')
      context.whatsappTransportOptions.transports[0].can_reply = false;
    if (change === 'inactive composer') context.isComposerActive = false;
    confirm(true);
    await sending;
    expect(context.$store.dispatch).not.toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith(
      expect.stringContaining('WHATSAPP_UNIFIED.PIX_CONFIRMATION_CHANGED')
    );
  });

  it('preserves the legacy Uno PIX flow without an inbox link', async () => {
    const context = createPixContext({
      whatsappTransportOptions: undefined,
      isAUnoapiChannel: true,
    });
    context.inbox = context.$store.getters['inboxes/getInbox'](1);
    expect(context.showPixPaymentButton).toBe(true);
    expect(context.pixPaymentConfirmationDescription).toContain(
      'CONVERSATION.REPLYBOX.PIX_PAYMENT.CONFIRM_DESCRIPTION'
    );
    await ReplyBox.methods.sendPixPayment.call(context);
    expect(context.$store.dispatch.mock.calls[0][1]).not.toHaveProperty(
      'whatsapp_transport'
    );
  });
});
