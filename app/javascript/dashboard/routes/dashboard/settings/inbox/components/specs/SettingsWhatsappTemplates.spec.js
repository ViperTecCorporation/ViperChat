import Settings from '../../Settings.vue';
import inboxMixin from 'shared/mixins/inboxMixin';
import WhatsappTemplates from '../WhatsappTemplates.vue';

describe('inbox settings Meta template tab', () => {
  it.each([
    ['Channel::Whatsapp', 'whatsapp_cloud', true, true],
    ['Channel::Whatsapp', 'whatsapp_cloud', false, false],
    ['Channel::Whatsapp', 'default', true, false],
    ['Channel::Whatsapp', 'unoapi', true, false],
    ['Channel::TwilioSms', 'whatsapp_cloud', true, false],
    ['Channel::Api', 'whatsapp_cloud', true, false],
  ])('gates %s / %s / admin=%s', (channelType, provider, isAdmin, expected) => {
    const context = {
      inbox: { channel_type: channelType, provider },
      isAdmin,
      isAWhatsAppCloudChannel: inboxMixin.computed.isAWhatsAppCloudChannel.call(
        {
          channelType,
          whatsAppAPIProvider: provider,
        }
      ),
      isFeatureEnabledonAccount: () => false,
      $t: key => key,
    };
    const tabs = Settings.computed.tabs.call(context);
    expect(tabs.some(tab => tab.key === 'whatsapp-templates')).toBe(expected);
    expect(Settings.components.WhatsappTemplates).toBe(WhatsappTemplates);
  });
});
