import enInbox from '../locale/en/inboxMgmt.json';
import ptInbox from '../locale/pt_BR/inboxMgmt.json';
import enConversation from '../locale/en/conversation.json';
import ptConversation from '../locale/pt_BR/conversation.json';
import enCampaign from '../locale/en/campaign.json';
import ptCampaign from '../locale/pt_BR/campaign.json';

describe('ViperConnect display branding', () => {
  it.each([enInbox, ptInbox])('preserves provider translation keys', locale => {
    expect(locale.INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.UNOAPI).toBe(
      'ViperConnect'
    );
    expect(locale.INBOX_MGMT.TABS.UNOAPI_CONFIGURATION).toContain(
      'ViperConnect'
    );
  });

  it.each([
    enInbox,
    ptInbox,
    enConversation,
    ptConversation,
    enCampaign,
    ptCampaign,
  ])('does not expose the old brand in labels or help text', locale => {
    const inspect = value => {
      if (typeof value === 'string') {
        expect(value).not.toMatch(/\b(?:UnoAPI|Unoapi|Uno API|UNO API)\b/);
      } else if (value && typeof value === 'object') {
        Object.values(value).forEach(inspect);
      }
    };
    inspect(locale);
  });
});
