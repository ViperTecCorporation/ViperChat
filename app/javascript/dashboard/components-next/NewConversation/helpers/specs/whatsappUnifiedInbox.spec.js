import camelcaseKeys from 'camelcase-keys';
import {
  buildContactableInboxesList,
  processContactableInboxes,
  getContactInboxes,
  prepareNewMessagePayload,
  prepareWhatsAppMessagePayload,
} from '../composeConversationHelper';
import {
  getWhatsappRouting,
  getWhatsappTransport,
} from '../whatsappUnifiedInbox';
import {
  createConversationPayload,
  createWhatsAppConversationPayload,
  actions,
} from 'dashboard/store/modules/contactConversations';
import ConversationApi from 'dashboard/api/conversations';
import { link, inboxes } from './whatsappUnifiedInbox.fixtures';

vi.mock('dashboard/api/conversations', () => ({
  default: { create: vi.fn() },
}));

describe('unified compose routing', () => {
  it.each(
    [inboxes, camelcaseKeys(inboxes, { deep: true }), [inboxes[1]]].map(
      list => [list]
    )
  )(
    'collapses raw, camelized and secondary-only lists to the authorized primary',
    list => {
      expect(buildContactableInboxesList(list)).toMatchObject([
        { id: 1, value: 1, name: 'Unified support' },
      ]);
      expect(buildContactableInboxesList(list)).toHaveLength(1);
    }
  );

  it('allows either provider to own the primary', () => {
    const reversed = inboxes.map(inbox => ({
      ...inbox,
      whatsapp_inbox_link: {
        ...link,
        primary_inbox_id: 2,
        secondary_inbox_id: 1,
        primary_inbox_name: 'Uno primary',
      },
    }));
    expect(buildContactableInboxesList(reversed)).toMatchObject([
      { id: 2, name: 'Uno primary' },
    ]);
  });

  it.each([
    { email: '123@g.us' },
    { source_id: '123@g.us' },
    { groupSourceId: '123@g.us' },
  ])('never collapses groups: %j', contact => {
    expect(buildContactableInboxesList(inboxes, contact)).toHaveLength(2);
    expect(getWhatsappRouting(inboxes[1], 'whatsapp_cloud', contact)).toEqual({
      inboxId: 2,
    });
  });

  it('keeps group source destinations physical without contact data', () => {
    expect(
      buildContactableInboxesList(
        inboxes.map(inbox => ({ ...inbox, source_id: '123@g.us' }))
      )
    ).toHaveLength(2);
  });

  it.each([null, { ...link, enabled: false }])(
    'does not merge absent or disabled metadata',
    metadata => {
      expect(
        buildContactableInboxesList(
          inboxes.map(inbox => ({ ...inbox, whatsapp_inbox_link: metadata }))
        )
      ).toHaveLength(2);
    }
  );

  it('handles direct raw contactable inbox results', () => {
    expect(
      buildContactableInboxesList(processContactableInboxes(inboxes))
    ).toHaveLength(1);
  });

  it('keeps the unified pair available for BSUID-only contacts even with Meta primary', () => {
    const contact = { id: 3, bsuid: 'business-scoped-id', contactInboxes: [] };
    const list = buildContactableInboxesList(
      getContactInboxes(contact, inboxes),
      contact
    );
    expect(list).toMatchObject([{ id: 1 }]);
    expect(getWhatsappTransport(list[0], 'unoapi').inboxId).toBe(2);
  });

  it('allows recipients without a contact and retains both transports', () => {
    expect(
      buildContactableInboxesList(
        getContactInboxes({ recipient: { bsuid: 'id' } }, inboxes)
      )
    ).toHaveLength(1);
  });

  it('rejects unknown transports instead of choosing a physical provider', () => {
    expect(() => getWhatsappRouting(inboxes[0], 'unknown')).toThrow(
      'CAPABILITY_UNAVAILABLE'
    );
    expect(() =>
      getWhatsappRouting({
        ...inboxes[0],
        whatsapp_inbox_link: { ...link, default_provider: 'unknown' },
      })
    ).toThrow();
  });

  it.each(['unoapi', 'whatsapp_cloud'])(
    'sends primary inbox and message transport in JSON and FormData: %s',
    provider => {
      const params = prepareNewMessagePayload({
        targetInbox: inboxes[1],
        selectedContact: { recipient: { bsuid: 'id' } },
        message: 'draft',
        currentUser: { id: 4 },
        whatsappTransport: provider,
      });
      expect(createWhatsAppConversationPayload({ params })).toMatchObject({
        inbox_id: 1,
        recipient: { bsuid: 'id' },
        message: { whatsapp_transport: provider },
      });
      const form = createConversationPayload({
        params,
        files: ['signed-blob'],
      });
      expect(form.get('inbox_id')).toBe('1');
      expect(form.get('message[whatsapp_transport]')).toBe(provider);
      expect(form.get('message[attachments][]')).toBe('signed-blob');
      expect(form.has('contact_id')).toBe(false);
    }
  );

  it('uses the default transport for template payloads and preserves recipients', () => {
    expect(
      prepareWhatsAppMessagePayload({
        targetInbox: inboxes[1],
        selectedContact: { recipient: { phone_number: '+5511' } },
        currentUser: { id: 4 },
        message: 'welcome',
        templateParams: { name: 'welcome' },
      })
    ).toMatchObject({
      inboxId: 1,
      contactId: undefined,
      recipient: { phone_number: '+5511' },
      message: {
        whatsapp_transport: 'unoapi',
        template_params: { name: 'welcome' },
      },
    });
  });

  it('does not drop Uno media when the caller uses WhatsApp mode', async () => {
    ConversationApi.create.mockResolvedValue({ data: { id: 8 } });
    await actions.create(
      { commit: vi.fn() },
      {
        params: {
          inboxId: 1,
          contactId: 3,
          message: { content: '', whatsapp_transport: 'unoapi' },
          files: ['signed-blob'],
        },
        isFromWhatsApp: true,
      }
    );
    const payload = ConversationApi.create.mock.calls[0][0];
    expect(payload).toBeInstanceOf(FormData);
    expect(payload.get('message[whatsapp_transport]')).toBe('unoapi');
    expect(payload.get('message[attachments][]')).toBe('signed-blob');
  });
});
