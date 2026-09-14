import {
  createConversationPayload,
  createWhatsAppConversationPayload,
} from 'dashboard/store/modules/contactConversations';
import {
  prepareNewMessagePayload,
  prepareWhatsAppMessagePayload,
} from '../composeConversationHelper';

describe('direct recipient payload', () => {
  const recipient = { phone_number: '+5566996222472' };
  const draft = { name: '+5566996222472', recipient };
  const input = {
    selectedContact: draft,
    targetInbox: { id: 1 },
    message: 'Hello',
    currentUser: { id: 2 },
  };

  it('preserves the provisional recipient through a JSON send', () => {
    const params = prepareWhatsAppMessagePayload(input);
    const payload = createWhatsAppConversationPayload({ params });
    expect(payload.recipient).toEqual(recipient);
    expect(payload.contact_id).toBeUndefined();
    expect(payload.message.content).toBe('Hello');
  });

  it('preserves the recipient through multipart without an invalid contact ID', () => {
    const params = prepareNewMessagePayload(input);
    const payload = createConversationPayload({ params });
    expect(payload.get('recipient[phone_number]')).toBe(recipient.phone_number);
    expect(payload.has('contact_id')).toBe(false);
    expect(payload.has('source_id')).toBe(false);
  });
});
