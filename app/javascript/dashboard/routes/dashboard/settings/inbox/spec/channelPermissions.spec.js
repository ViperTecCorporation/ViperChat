import { ref, nextTick } from 'vue';
import { shallowMount } from '@vue/test-utils';
import ChannelList from '../ChannelList.vue';
import Whatsapp from '../channels/Whatsapp.vue';
import ChannelItem from 'dashboard/components/widgets/ChannelItem.vue';

vi.mock('../channels/Twilio.vue', () => ({
  default: { name: 'Twilio', template: '<div />' },
}));
vi.mock('../channels/Unoapi.vue', () => ({
  default: { name: 'Unoapi', template: '<div />' },
}));
vi.mock('../channels/CloudWhatsapp.vue', () => ({
  default: { name: 'CloudWhatsapp', template: '<div />' },
}));
vi.mock('../channels/360DialogWhatsapp.vue', () => ({
  default: { name: 'ThreeSixtyDialogWhatsapp', template: '<div />' },
}));
vi.mock('../channels/WhatsappEmbeddedSignup.vue', () => ({
  default: { name: 'WhatsappEmbeddedSignup', template: '<div />' },
}));

const state = vi.hoisted(() => ({ account: null, route: null, push: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: state.account,
    accountId: ref(1),
    isOnChatwootCloud: ref(false),
    isCloudFeatureEnabled: () => false,
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref({}),
}));
vi.mock('vue-router', () => ({
  useRoute: () => state.route,
  useRouter: () => ({ push: state.push }),
}));

describe('WhatsApp creation permissions', () => {
  it.each([true, false])('respects the API channel flag: %s', enabled => {
    const wrapper = shallowMount(ChannelItem, {
      props: {
        channel: { key: 'api', title: 'API', icon: 'i-lucide-code' },
        enabledFeatures: { channel_api: enabled, api_and_webhooks: true },
      },
    });
    wrapper.findComponent({ name: 'ChannelSelector' }).vm.$emit('click');
    expect(Boolean(wrapper.emitted('channelItemClick'))).toBe(enabled);
  });

  it.each([true, false])(
    'respects embedded signup on self-hosted accounts: %s',
    enabled => {
      state.account = ref({
        features: {
          channel_whatsapp: true,
          whatsapp_embedded_signup_inbox_creation: enabled,
        },
      });
      state.route = { query: { provider: 'whatsapp' } };
      const previousConfig = window.chatwootConfig;
      window.chatwootConfig = { whatsappAppId: 'test-app' };
      try {
        const wrapper = shallowMount(Whatsapp);
        expect(wrapper.find('whatsapp-embedded-signup-stub').exists()).toBe(
          enabled
        );
        expect(wrapper.find('cloud-whatsapp-stub').exists()).toBe(!enabled);
      } finally {
        window.chatwootConfig = previousConfig;
      }
    }
  );
  beforeEach(() => {
    state.account = ref({
      features: { channel_whatsapp: true, disable_channel_unoapi: false },
    });
    state.route = {
      name: 'settings_inboxes_page_channel',
      params: { accountId: 1 },
      query: {},
    };
  });

  it.each([
    [true, false, true, true],
    [false, false, false, true],
    [true, true, true, false],
    [false, true, false, false],
  ])(
    'hides disallowed cards: official=%s unoBlocked=%s',
    (official, unoBlocked, whatsappVisible, unoVisible) => {
      state.account.value.features = {
        channel_whatsapp: official,
        disable_channel_unoapi: unoBlocked,
      };
      const wrapper = shallowMount(ChannelList);
      const keys = wrapper
        .findAllComponents(ChannelItem)
        .map(item => item.props('channel').key);
      expect(keys.includes('whatsapp')).toBe(whatsappVisible);
      expect(keys.includes('unoapi')).toBe(unoVisible);
    }
  );

  it('reacts when the current account changes', async () => {
    const wrapper = shallowMount(ChannelList);
    state.account.value = {
      features: { channel_whatsapp: false, disable_channel_unoapi: true },
    };
    await nextTick();
    expect(
      wrapper
        .findAllComponents(ChannelItem)
        .map(item => item.props('channel').key)
    ).not.toContain('unoapi');
  });

  it.each(['unoapi', 'whatsapp', 'twilio', 'whatsapp_manual', '360dialog'])(
    'blocks a direct route to %s',
    provider => {
      state.account.value.features = {
        channel_whatsapp: false,
        disable_channel_unoapi: true,
      };
      state.route.query.provider = provider;
      const wrapper = shallowMount(Whatsapp);
      expect(wrapper.find('[role="alert"]').exists()).toBe(true);
      expect(wrapper.find('unoapi-stub').exists()).toBe(false);
      expect(wrapper.find('cloud-whatsapp-stub').exists()).toBe(false);
      expect(wrapper.find('twilio-stub').exists()).toBe(false);
    }
  );

  it('shows UnoAPI when official WhatsApp is disabled', () => {
    state.account.value.features.channel_whatsapp = false;
    state.route.query.provider = 'unoapi';
    const wrapper = shallowMount(Whatsapp);
    expect(wrapper.find('unoapi-stub').exists()).toBe(true);
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });

  it('shows a restriction message when no provider is allowed', () => {
    state.account.value.features = {
      channel_whatsapp: false,
      disable_channel_unoapi: true,
    };
    expect(shallowMount(Whatsapp).find('[role="alert"]').exists()).toBe(true);
  });

  it('routes the separate UnoAPI card to its provider', () => {
    const wrapper = shallowMount(ChannelList);
    const item = wrapper
      .findAllComponents(ChannelItem)
      .find(card => card.props('channel').key === 'unoapi');
    item.vm.$emit('channelItemClick', 'unoapi');
    expect(state.push).toHaveBeenCalledWith({
      name: 'settings_inboxes_page_channel',
      params: { accountId: 1, sub_page: 'whatsapp' },
      query: { provider: 'unoapi' },
    });
  });
});
