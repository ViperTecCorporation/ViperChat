import Settings from '../Settings.vue';

describe('Gmail history tab', () => {
  it.each([
    ['Channel::Email', 'google', true],
    ['Channel::Email', 'microsoft', false],
    ['Channel::Email', undefined, false],
    ['Channel::Whatsapp', 'unoapi', false],
  ])(
    'limits history to supported inboxes: %s / %s',
    (channelType, provider, expected) => {
      const tabs = Settings.computed.tabs.call({
        inbox: { channel_type: channelType, provider },
        $t: key => key,
        isFeatureEnabledonAccount: () => false,
      });
      expect(tabs.some(tab => tab.key === 'import-history')).toBe(expected);
    }
  );
});
