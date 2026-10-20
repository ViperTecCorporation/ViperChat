import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import AccountHealth from '../AccountHealth.vue';
import en from 'dashboard/i18n/locale/en/inboxMgmt.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/inboxMgmt.json';

describe('AccountHealth messaging limit', () => {
  it.each([
    ['en', '2K customers per 24h'],
    ['pt_BR', '2 mil clientes por 24 h'],
  ])('shows the normalized current 2K tier in %s', (locale, expected) => {
    const wrapper = mount(AccountHealth, {
      props: {
        inboxId: 7,
        healthData: {
          messaging_limit_tier: 'TIER_2K',
          messaging_limit_scope: 'business_portfolio',
          fetched_at: '2026-10-17T12:00:00Z',
        },
      },
      global: {
        plugins: [
          createI18n({ legacy: false, locale, messages: { en, pt_BR: ptBR } }),
        ],
        stubs: {
          AccountInsights: true,
          MetaWebhookEvents: true,
          ButtonV4: true,
          Icon: true,
        },
      },
    });
    expect(wrapper.text()).toContain(expected);
    expect(wrapper.text()).toContain(
      locale === 'en'
        ? 'Shared business portfolio'
        : 'Limite compartilhado do portfólio'
    );
    expect(wrapper.text()).toContain(
      locale === 'en' ? 'Health data fetched' : 'Dados de saúde consultados'
    );
    expect(
      wrapper.findComponent({ name: 'AccountInsights' }).props('inboxId')
    ).toBe(7);
    expect(
      wrapper.findComponent({ name: 'MetaWebhookEvents' }).props('inboxId')
    ).toBe(7);
    expect(wrapper.html().indexOf('account-insights-stub')).toBeLessThan(
      wrapper.html().indexOf('meta-webhook-events-stub')
    );
    wrapper.unmount();
  });

  it.each([null, 'UNRECOGNIZED_FUTURE_TIER'])(
    'renders unknown tier %s safely without falling back to a legacy value',
    tier => {
      const wrapper = mount(AccountHealth, {
        props: {
          inboxId: 7,
          healthData: {
            messaging_limit_tier: tier,
            messaging_limit_scope: 'unknown',
            messaging_limit: 'TIER_1K',
          },
        },
        global: {
          stubs: {
            AccountInsights: true,
            MetaWebhookEvents: true,
            ButtonV4: true,
            Icon: true,
          },
        },
      });
      expect(wrapper.text()).toContain('Messaging limit unavailable');
      expect(wrapper.text()).toContain('Limit scope is unavailable');
      expect(wrapper.text()).not.toContain('UNRECOGNIZED_FUTURE_TIER');
      expect(wrapper.text()).not.toContain('1K customers');
      expect(wrapper.text()).not.toContain('VALUES.TIERS');
      wrapper.unmount();
    }
  );
});
