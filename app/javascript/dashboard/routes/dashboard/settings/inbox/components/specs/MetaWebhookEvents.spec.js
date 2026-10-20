import { flushPromises, mount } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAdmin } from 'dashboard/composables/useAdmin';
import InboxesAPI from 'dashboard/api/inboxes';
import en from 'dashboard/i18n/locale/en/inboxMgmt.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/inboxMgmt.json';
import MetaWebhookEvents from '../MetaWebhookEvents.vue';

vi.mock('vue-router', () => ({ useRoute: vi.fn() }));
vi.mock('dashboard/composables/useAdmin', () => ({ useAdmin: vi.fn() }));

describe('MetaWebhookEvents', () => {
  let wrapper;
  let get;
  let patch;
  let payload;
  let route;
  let isAdmin;

  beforeEach(() => {
    get = vi.fn();
    patch = vi.fn();
    vi.stubGlobal('axios', { get, patch });
    route = reactive({ params: { accountId: '9' } });
    isAdmin = ref(true);
    useRoute.mockReturnValue(route);
    useAdmin.mockReturnValue({ isAdmin });
    vi.spyOn(InboxesAPI, 'url', 'get').mockImplementation(
      () => `/api/v1/accounts/${route.params.accountId}/inboxes`
    );
    payload = {
      graph_version: 'v26.0',
      session_info_version: '3',
      supported_fields: ['history', 'smb_app_state_sync', 'account_update'],
      events: [],
      history_settings: {
        ignore_history_messages: true,
        ignore_group_messages: false,
        history_max_age_days: 7,
      },
    };
    get.mockImplementation(() => Promise.resolve({ data: payload }));
    patch.mockImplementation((url, settings) =>
      Promise.resolve({ data: { history_settings: settings } })
    );
  });

  afterEach(() => {
    wrapper?.unmount();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  const render = (locale = 'en') => {
    wrapper = mount(MetaWebhookEvents, {
      props: { inboxId: 4 },
      global: {
        plugins: [
          createI18n({ legacy: false, locale, messages: { en, pt_BR: ptBR } }),
        ],
        stubs: {
          ButtonV4: {
            props: ['disabled', 'isLoading'],
            template: '<button :disabled="disabled"><slot /></button>',
          },
        },
      },
    });
    return wrapper;
  };

  it('loads an account/inbox-scoped summary, separates Graph and session format, and handles empty events', async () => {
    render();
    expect(wrapper.attributes('aria-busy')).toBe('true');
    expect(wrapper.get('[role="status"]').text()).toContain('Loading');
    await flushPromises();
    expect(get).toHaveBeenCalledExactlyOnceWith(
      '/api/v1/accounts/9/inboxes/4/management_events'
    );
    expect(wrapper.text()).toContain('No events received');
    expect(wrapper.findAll('dd').map(node => node.text())).toEqual([
      'v26.0',
      '3',
    ]);
    expect(wrapper.text()).toContain('sessionInfoVersion');
    expect(wrapper.text()).not.toMatch(/Embedded v4/i);
    expect(wrapper.text()).toContain('Meta app panel');
    expect(wrapper.get('details summary').text()).toContain(
      'Supported technical fields'
    );
    expect(wrapper.get('input[type="checkbox"]').element.checked).toBe(true);
    expect(wrapper.find('input[type="number"]').exists()).toBe(false);
    expect(patch).not.toHaveBeenCalled();
  });

  it('distinguishes pending history import, processed events and contact review, limiting the list to 25', async () => {
    payload.events = Array.from({ length: 26 }, (_, index) => ({
      id: index,
      field: index === 0 ? 'history' : 'smb_app_state_sync',
      state: ['pending_import', 'processed'][index] || 'review',
      received_at: '2026-10-17T12:00:00Z',
      reason: index === 0 ? 'automatic_import_pending' : null,
      details: { contacts_count: 2 },
    }));
    render();
    await flushPromises();
    const events = wrapper.findAll('[data-testid="management-event"]');
    expect(events).toHaveLength(25);
    expect(events[0].text()).toContain('Import pending');
    expect(events[0].text()).toContain('Awaiting automatic import processing');
    expect(events[1].text()).toContain('Processed');
    expect(events[2].text()).toContain('Requires review');
    expect(events[0].text()).toContain('Received at');
    expect(events[0].text()).not.toContain('Invalid Date');
    expect(wrapper.text()).toContain('remains review-only');
    expect(wrapper.text()).toContain('automatically imports received history');
    expect(wrapper.text()).toContain(
      'without duplicating messages, contacts or media'
    );
    expect(wrapper.text()).toContain(
      'does not trigger notifications or reopen resolved conversations'
    );
    expect(wrapper.text()).toContain('without forcing a contact association');
  });

  it('shows only whitelisted safe counts, tiers and quality without secret payloads', async () => {
    payload.events = [
      {
        id: 1,
        field: 'account_update',
        state: 'recorded',
        received_at: 'invalid',
        payload: { access_token: 'secret-token' },
        details: {
          messages_count: 0,
          contacts_count: 2,
          history_count: 1,
          imported_messages_count: 3,
          duplicate_messages_count: 4,
          pending_messages_count: 5,
          failed_messages_count: 6,
          max_daily_conversations_per_business: 'TIER_2K',
          quality_rating: 'GREEN',
          access_token: 'secret-token',
          messages: [{ text: 'private message' }],
          contacts: [{ name: 'private name' }],
          arbitrary: 'raw-value',
        },
      },
      {
        id: 2,
        field: 'history',
        state: 'review',
        reason: 'secret-reason',
        details: {
          messages_count: 'secret-count',
          contacts_count: -1,
          history_count: {},
          imported_messages_count: 'secret-imported',
          duplicate_messages_count: -1,
          pending_messages_count: 1.5,
          failed_messages_count: Number.MAX_SAFE_INTEGER + 1,
          quality_rating: 'secret-quality',
          max_daily_conversations_per_business: 'secret-tier',
        },
      },
    ];
    render();
    await flushPromises();
    const html = wrapper.html();
    [
      'secret',
      'private message',
      'private name',
      'raw-value',
      'access_token',
      '[object Object]',
    ].forEach(value => {
      expect(html).not.toContain(value);
    });
    expect(wrapper.text()).toContain('TIER_2K');
    expect(wrapper.text()).toContain('High');
    expect(wrapper.text()).toContain('Messages reported');
    const events = wrapper.findAll('[data-testid="management-event"]');
    expect(events[0].findAll('dd').map(node => node.text())).toEqual([
      '0',
      '2',
      '1',
      '3',
      '4',
      '5',
      '6',
      'TIER_2K',
      'High',
    ]);
    expect(events[1].findAll('dd')).toHaveLength(0);
    expect(wrapper.text()).toContain('Received and recorded');
    expect(wrapper.text()).toContain('Unavailable');
  });

  it('wraps long technical fields and supports Portuguese with all safety notices', async () => {
    const field = `technical_${'x'.repeat(100)}`;
    payload.events = [{ id: 1, field, state: 'pending_import' }];
    payload.supported_fields = [field];
    render('pt_BR');
    await flushPromises();
    expect(wrapper.text()).toContain('Ignorar mensagens de histórico');
    expect(wrapper.text()).toContain('Importação pendente');
    expect(wrapper.text()).toContain('são importadas automaticamente');
    expect(wrapper.text()).toContain('não apaga mensagens existentes');
    expect(wrapper.text()).toContain(
      'sem sincronização automática de contatos'
    );
    expect(wrapper.text()).toContain(
      'não gera notificações nem reabre conversas resolvidas'
    );
    expect(
      wrapper.get('[data-testid="management-event"] .font-mono').classes()
    ).toContain('[overflow-wrap:anywhere]');
    expect(wrapper.get('details li').classes()).toContain(
      '[overflow-wrap:anywhere]'
    );
    expect(wrapper.text()).not.toContain('INBOX_MGMT.');
  });

  it.each(['en', 'pt_BR'])(
    'translates all automatic import reasons and counters in %s',
    async locale => {
      const reasons = [
        'automatic_import_pending',
        'import_identity_pending',
        'import_failed',
        'unsupported_history_message',
      ];
      payload.events = reasons.map((reason, id) => ({
        id,
        field: 'history',
        state: 'pending_import',
        reason,
        details: {
          imported_messages_count: 0,
          duplicate_messages_count: 0,
          pending_messages_count: 0,
          failed_messages_count: 0,
        },
      }));
      render(locale);
      await flushPromises();
      const translations = (locale === 'en' ? en : ptBR).INBOX_MGMT
        .META_WEBHOOK_EVENTS;
      const events = wrapper.findAll('[data-testid="management-event"]');
      reasons.forEach((reason, index) => {
        expect(events[index].text()).toContain(translations.REASONS[reason]);
        expect(events[index].findAll('dd')).toHaveLength(4);
        expect(events[index].text()).not.toContain('INBOX_MGMT.');
      });
    }
  );

  it('saves only manually with a Boolean and integer, then applies the returned settings', async () => {
    render();
    await flushPromises();
    await wrapper.get('input[type="checkbox"]').setValue(false);
    const days = wrapper.get('input[type="number"]');
    expect(days.element.value).toBe('7');
    expect(days.attributes('max')).toBe('3650');
    await days.setValue('30');
    expect(patch).not.toHaveBeenCalled();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(patch).toHaveBeenCalledExactlyOnceWith(
      '/api/v1/accounts/9/inboxes/4/coexistence_settings',
      {
        ignore_history_messages: false,
        ignore_group_messages: false,
        history_max_age_days: 30,
      }
    );
    expect(wrapper.text()).toContain('History settings saved.');
    await wrapper.get('input[type="checkbox"]').setValue(true);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(patch).toHaveBeenLastCalledWith(
      '/api/v1/accounts/9/inboxes/4/coexistence_settings',
      {
        ignore_history_messages: true,
        ignore_group_messages: false,
        history_max_age_days: 30,
      }
    );
  });

  it.each(['', '0', '-1', '3651', '1.5'])(
    'rejects invalid max age %j without making a PATCH',
    async value => {
      render();
      await flushPromises();
      await wrapper.get('input[type="checkbox"]').setValue(false);
      await wrapper.get('input[type="number"]').setValue(value);
      expect(
        wrapper.get('button[type="submit"]').attributes('disabled')
      ).toBeDefined();
      expect(wrapper.get('[role="alert"]').text()).toContain(
        'whole number between 1 and 3650'
      );
      await wrapper.get('form').trigger('submit');
      expect(patch).not.toHaveBeenCalled();
    }
  );

  it.each([1, 3650])('accepts the age boundary %i', async days => {
    render();
    await flushPromises();
    await wrapper.get('input[type="checkbox"]').setValue(false);
    await wrapper.get('input[type="number"]').setValue(String(days));
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(patch.mock.calls[0][1]).toEqual({
      ignore_history_messages: false,
      ignore_group_messages: false,
      history_max_age_days: days,
    });
  });

  it('uses conservative defaults if settings are absent', async () => {
    delete payload.history_settings;
    render();
    await flushPromises();
    expect(wrapper.get('input[type="checkbox"]').element.checked).toBe(true);
    expect(wrapper.get('[data-testid="ignore-groups"]').element.checked).toBe(
      false
    );
    await wrapper.get('input[type="checkbox"]').setValue(false);
    expect(wrapper.get('input[type="number"]').element.value).toBe('7');
  });

  it('saves group filtering independently without changing history or making automatic requests', async () => {
    render();
    await flushPromises();
    await wrapper.get('[data-testid="ignore-groups"]').setValue(true);
    expect(wrapper.get('input[type="checkbox"]').element.checked).toBe(true);
    expect(wrapper.find('input[type="number"]').exists()).toBe(false);
    expect(patch).not.toHaveBeenCalled();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(patch).toHaveBeenCalledExactlyOnceWith(
      '/api/v1/accounts/9/inboxes/4/coexistence_settings',
      {
        ignore_history_messages: true,
        ignore_group_messages: true,
        history_max_age_days: 7,
      }
    );
    expect(wrapper.get('[data-testid="ignore-groups"]').element.checked).toBe(
      true
    );
    await wrapper.get('input[type="checkbox"]').setValue(false);
    expect(wrapper.get('[data-testid="ignore-groups"]').element.checked).toBe(
      true
    );
  });

  it.each([undefined, null, false, 'true', 'false'])(
    'does not enable group filtering for non-true value %j',
    async value => {
      payload.history_settings.ignore_group_messages = value;
      render();
      await flushPromises();
      expect(wrapper.get('[data-testid="ignore-groups"]').element.checked).toBe(
        false
      );
    }
  );

  it.each(['en', 'pt_BR'])(
    'renders the independent group notice in %s',
    async locale => {
      payload.history_settings.ignore_group_messages = true;
      render(locale);
      await flushPromises();
      const translations = (locale === 'en' ? en : ptBR).INBOX_MGMT
        .META_WEBHOOK_EVENTS;
      const checkbox = wrapper.get('[data-testid="ignore-groups"]');
      expect(checkbox.element.checked).toBe(true);
      expect(wrapper.text()).toContain(translations.IGNORE_GROUPS);
      expect(
        wrapper.get(`#${checkbox.attributes('aria-describedby')}`).text()
      ).toBe(translations.IGNORE_GROUPS_NOTICE);
    }
  );

  it('uses the authoritative saved settings returned by the server', async () => {
    patch.mockResolvedValueOnce({
      data: {
        history_settings: {
          ignore_history_messages: false,
          ignore_group_messages: true,
          history_max_age_days: 14,
        },
      },
    });
    render();
    await flushPromises();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.get('input[type="checkbox"]').element.checked).toBe(false);
    expect(wrapper.get('input[type="number"]').element.value).toBe('14');
    expect(wrapper.get('[data-testid="ignore-groups"]').element.checked).toBe(
      true
    );
  });

  it('refetches when only the account changes, even with an identical inbox ID', async () => {
    render();
    await flushPromises();
    route.params.accountId = '15';
    await flushPromises();
    expect(get).toHaveBeenCalledTimes(2);
    expect(get).toHaveBeenLastCalledWith(
      '/api/v1/accounts/15/inboxes/4/management_events'
    );
  });

  it('hides the section and makes no requests for a non-admin', async () => {
    isAdmin.value = false;
    render();
    await flushPromises();
    expect(wrapper.find('section').exists()).toBe(false);
    expect(get).not.toHaveBeenCalled();
    expect(patch).not.toHaveBeenCalled();
  });

  it('keeps errors generic and allows explicit retry for loading and saving', async () => {
    get.mockRejectedValueOnce(new Error('secret upstream failure'));
    patch.mockRejectedValueOnce(new Error('secret save failure'));
    render();
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('Could not load');
    await wrapper.get('button').trigger('click');
    await flushPromises();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('Could not save');
    expect(wrapper.html()).not.toContain('secret');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.text()).toContain('History settings saved.');
  });

  it('refetches on tenant and inbox changes and ignores a stale fetch', async () => {
    let resolveFirst;
    get.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveFirst = resolve;
        })
    );
    render();
    route.params.accountId = '12';
    await wrapper.setProps({ inboxId: 8 });
    await flushPromises();
    expect(get).toHaveBeenLastCalledWith(
      '/api/v1/accounts/12/inboxes/8/management_events'
    );
    resolveFirst({
      data: {
        ...payload,
        graph_version: 'v22.0',
        history_settings: {
          ignore_history_messages: false,
          history_max_age_days: 99,
        },
      },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('v22.0');
    expect(wrapper.get('input[type="checkbox"]').element.checked).toBe(true);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(patch).toHaveBeenLastCalledWith(
      '/api/v1/accounts/12/inboxes/8/coexistence_settings',
      {
        ignore_history_messages: true,
        ignore_group_messages: false,
        history_max_age_days: 7,
      }
    );
  });

  it('ignores a stale save after switching inbox and prevents duplicate saves', async () => {
    let resolveSave;
    patch.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveSave = resolve;
        })
    );
    render();
    await flushPromises();
    await wrapper.get('input[type="checkbox"]').setValue(false);
    await wrapper.get('form').trigger('submit');
    await wrapper.get('form').trigger('submit');
    expect(patch).toHaveBeenCalledTimes(1);
    expect(wrapper.get('input').attributes('disabled')).toBeDefined();
    expect(
      wrapper.get('[data-testid="ignore-groups"]').attributes('disabled')
    ).toBeDefined();
    await wrapper.setProps({ inboxId: 8 });
    await flushPromises();
    resolveSave({
      data: {
        history_settings: {
          ignore_history_messages: false,
          history_max_age_days: 99,
        },
      },
    });
    await flushPromises();
    expect(wrapper.get('input[type="checkbox"]').element.checked).toBe(true);
    expect(wrapper.text()).not.toContain('History settings saved.');
  });

  it('invalidates pending data when admin access is lost', async () => {
    let resolveFirst;
    get.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveFirst = resolve;
        })
    );
    render();
    isAdmin.value = false;
    await flushPromises();
    resolveFirst({ data: payload });
    await flushPromises();
    expect(wrapper.find('section').exists()).toBe(false);
    expect(patch).not.toHaveBeenCalled();
  });
});
