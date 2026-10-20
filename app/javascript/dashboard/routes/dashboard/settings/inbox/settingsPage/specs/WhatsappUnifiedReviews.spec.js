import { mount, flushPromises } from '@vue/test-utils';
import { useRoute } from 'vue-router';
import WhatsappUnifiedReviews from '../WhatsappUnifiedReviews.vue';
import Inboxes from 'dashboard/api/inboxes';
import en from 'dashboard/i18n/locale/en/whatsappUnified.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/whatsappUnified.json';

vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: vi.fn(),
}));

vi.mock('dashboard/api/inboxes', () => ({
  default: {
    getWhatsappLinkReviews: vi.fn(),
    recheckWhatsappLinkReview: vi.fn(),
    acknowledgeWhatsappLinkReview: vi.fn(),
  },
}));

const item = {
  id: 'event-123',
  kind: 'event',
  state: 'review',
  reason: 'identity_pending',
  provider: 'whatsapp_cloud',
  original_id: 'original-opaque-id',
  public_id: 'wamid.public',
  message_id: 45,
  conversation_id: 12,
  conversation_display_id: 3,
  created_at: '2026-10-16T11:00:00Z',
  updated_at: '2026-10-16T11:01:00Z',
  attempts: 12,
  next_attempt_at: null,
  version: 'review-version-1',
  reviewed_at: null,
  reviewed_by_id: null,
  actions: { recheck: true, acknowledge: true },
};
const response = {
  data: {
    items: [item],
    meta: { page: 1, total: 1, total_pages: 1 },
  },
};
const options = {
  props: { inboxId: 1, linkEnabled: true },
  global: {
    mocks: { $t: key => key },
    stubs: {
      NextButton: false,
      RouterLink: {
        name: 'RouterLink',
        props: ['to'],
        template: '<a><slot /></a>',
      },
    },
  },
};
const button = (wrapper, name) =>
  wrapper
    .findAll('button')
    .find(el => el.text() === `WHATSAPP_UNIFIED.REVIEWS.${name}`);

describe('unified inbox administrative review', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    useRoute.mockReturnValue({ params: { accountId: '7' } });
    Inboxes.getWhatsappLinkReviews.mockResolvedValue(response);
    Inboxes.recheckWhatsappLinkReview.mockResolvedValue({ data: { item } });
    Inboxes.acknowledgeWhatsappLinkReview.mockResolvedValue({ data: { item } });
  });

  it('links to the display ID in the current account, never to the internal conversation ID', async () => {
    const wrapper = mount(WhatsappUnifiedReviews, options);
    await flushPromises();
    expect(wrapper.findComponent({ name: 'RouterLink' }).props('to')).toEqual({
      name: 'inbox_conversation',
      params: { accountId: '7', conversation_id: 3 },
    });
    wrapper.unmount();
  });

  it.each([null, undefined])(
    'does not guess a conversation shortcut without display ID %s',
    async displayId => {
      Inboxes.getWhatsappLinkReviews.mockResolvedValue({
        data: {
          ...response.data,
          items: [{ ...item, conversation_display_id: displayId }],
        },
      });
      const wrapper = mount(WhatsappUnifiedReviews, options);
      await flushPromises();
      expect(wrapper.findComponent({ name: 'RouterLink' }).exists()).toBe(
        false
      );
      wrapper.unmount();
    }
  );

  it('does not build a conversation shortcut without the current account route', async () => {
    useRoute.mockReturnValue({ params: {} });
    const wrapper = mount(WhatsappUnifiedReviews, options);
    await flushPromises();
    expect(wrapper.findComponent({ name: 'RouterLink' }).exists()).toBe(false);
    wrapper.unmount();
  });

  it.each(Object.keys(en.WHATSAPP_UNIFIED.REVIEWS.REASONS))(
    'translates known service review reason %s in both locales',
    async reason => {
      Inboxes.getWhatsappLinkReviews.mockResolvedValue({
        data: { ...response.data, items: [{ ...item, kind: 'media', reason }] },
      });
      const wrapper = mount(WhatsappUnifiedReviews, options);
      await flushPromises();
      expect(wrapper.text()).toContain(
        `WHATSAPP_UNIFIED.REVIEWS.REASONS.${reason}`
      );
      expect(en.WHATSAPP_UNIFIED.REVIEWS.REASONS[reason]).toBeTruthy();
      expect(ptBR.WHATSAPP_UNIFIED.REVIEWS.REASONS[reason]).toBeTruthy();
      expect(wrapper.find('h5').text()).toBe(
        `WHATSAPP_UNIFIED.REVIEWS.REASONS.${reason}`
      );
      expect(wrapper.find('[data-review-guidance]').text()).toBe(
        `WHATSAPP_UNIFIED.REVIEWS.GUIDANCE.${reason}`
      );
      expect(en.WHATSAPP_UNIFIED.REVIEWS.GUIDANCE[reason]).toBeTruthy();
      expect(ptBR.WHATSAPP_UNIFIED.REVIEWS.GUIDANCE[reason]).toBeTruthy();
      wrapper.unmount();
    }
  );

  it.each([
    [
      en,
      'Waiting for the message from the other channel',
      'automatically waits',
      'not conflicting evidence',
      'without resending the message or starting another file download',
    ],
    [
      ptBR,
      'Aguardando a mensagem do outro canal',
      'aguarda automaticamente',
      'não um conflito de evidências',
      'sem reenviar a mensagem nem iniciar outro download',
    ],
  ])(
    'renders counterpart_pending as automatic waiting, not a conflict, in each locale',
    async (locale, title, waiting, distinction, guidance) => {
      Inboxes.getWhatsappLinkReviews.mockResolvedValue({
        data: {
          ...response.data,
          items: [
            {
              ...item,
              kind: 'media',
              state: 'pending',
              reason: 'counterpart_pending',
            },
          ],
        },
      });
      const wrapper = mount(WhatsappUnifiedReviews, {
        ...options,
        global: {
          ...options.global,
          mocks: {
            $t: key =>
              key.split('.').reduce((value, part) => value?.[part], locale) ??
              key,
          },
        },
      });
      await flushPromises();
      expect(wrapper.find('h5').text()).toBe(title);
      const explanation = wrapper.find('[data-review-guidance]');
      expect(explanation.text()).toContain(waiting);
      expect(explanation.text()).toContain(distinction);
      expect(explanation.text()).toContain(guidance);
      expect(explanation.element.closest('details')).toBeNull();
      expect(wrapper.find('details').element.open).toBe(false);
      expect(Inboxes.recheckWhatsappLinkReview).not.toHaveBeenCalled();
      expect(Inboxes.acknowledgeWhatsappLinkReview).not.toHaveBeenCalled();
      wrapper.unmount();
    }
  );

  it('keeps human context and action explanations outside collapsed technical details', async () => {
    const wrapper = mount(WhatsappUnifiedReviews, options);
    await flushPromises();
    const card = wrapper.find('[data-review-id]');
    const details = card.find('details');
    expect(details.element.open).toBe(false);
    expect(details.find('summary').text()).toBe(
      'WHATSAPP_UNIFIED.REVIEWS.TECHNICAL_DETAILS'
    );
    [item.id, item.original_id, item.public_id, item.created_at].forEach(
      value => {
        expect(details.text()).toContain(value);
      }
    );
    expect(details.text()).not.toContain(
      'WHATSAPP_UNIFIED.REVIEWS.STATES.review'
    );
    expect(card.find('h5').text()).not.toContain(item.id);
    expect(card.find('dl').text()).toContain(
      'WHATSAPP_UNIFIED.REVIEWS.STATES.review'
    );
    expect(card.find('dl').text()).toContain(
      'WHATSAPP_UNIFIED.REVIEWS.FIELDS.conversation_display_id'
    );
    expect(card.find('dl').text()).toContain('3');
    expect(wrapper.text()).toContain('WHATSAPP_UNIFIED.REVIEWS.RECHECK_HELP');
    expect(wrapper.text()).toContain(
      'WHATSAPP_UNIFIED.REVIEWS.ACKNOWLEDGE_HELP'
    );
    expect(details.find('button').exists()).toBe(false);
    wrapper.unmount();
  });

  it.each(['new_service_reason', '<img src=x onerror=alert(1)>', null])(
    'retains unknown reason %s with safe generic guidance',
    async reason => {
      Inboxes.getWhatsappLinkReviews.mockResolvedValue({
        data: {
          ...response.data,
          items: [
            {
              ...item,
              kind: 'future_kind',
              reason,
              state: 'future_state',
              conversation_display_id: null,
            },
          ],
        },
      });
      const wrapper = mount(WhatsappUnifiedReviews, options);
      await flushPromises();
      expect(wrapper.find('h5').text()).toBe(
        reason || 'WHATSAPP_UNIFIED.REVIEWS.UNKNOWN_REASON'
      );
      expect(wrapper.find('[data-review-guidance]').text()).toBe(
        'WHATSAPP_UNIFIED.REVIEWS.UNKNOWN_GUIDANCE'
      );
      expect(wrapper.text()).toContain('future_state');
      expect(wrapper.text()).toContain('WHATSAPP_UNIFIED.REVIEWS.UNKNOWN_KIND');
      expect(wrapper.text()).toContain(
        'WHATSAPP_UNIFIED.REVIEWS.NO_CONVERSATION'
      );
      expect(wrapper.find('details').text()).toContain('future_kind');
      expect(wrapper.find('img').exists()).toBe(false);
      expect(button(wrapper, 'RECHECK')).toBeDefined();
      wrapper.unmount();
    }
  );

  it('loads scoped records and displays only whitelisted technical fields', async () => {
    Inboxes.getWhatsappLinkReviews.mockResolvedValue({
      data: {
        ...response.data,
        items: [
          {
            ...item,
            payload: { body: 'PRIVATE_PAYLOAD' },
            access_token: 'SECRET_TOKEN',
          },
        ],
      },
    });
    const wrapper = mount(WhatsappUnifiedReviews, options);
    expect(wrapper.text()).toContain('WHATSAPP_UNIFIED.REVIEWS.LOADING');
    await flushPromises();
    expect(Inboxes.getWhatsappLinkReviews).toHaveBeenCalledWith(1, {
      page: 1,
      kind: 'event',
      status: 'open',
    });
    expect(wrapper.text()).toContain(item.original_id);
    expect(wrapper.text()).toContain(
      'WHATSAPP_UNIFIED.REVIEWS.REASONS.identity_pending'
    );
    expect(wrapper.text()).not.toContain('PRIVATE_PAYLOAD');
    expect(wrapper.text()).not.toContain('SECRET_TOKEN');
    expect(wrapper.text()).not.toContain(item.version);
    wrapper.unmount();
  });

  it.each(['RECHECK', 'ACKNOWLEDGE'])(
    'requires explicit confirmation before %s and can cancel',
    async action => {
      const wrapper = mount(WhatsappUnifiedReviews, options);
      await flushPromises();
      await button(wrapper, action).trigger('click');
      expect(wrapper.find('[role=group]').exists()).toBe(true);
      expect(Inboxes.recheckWhatsappLinkReview).not.toHaveBeenCalled();
      expect(Inboxes.acknowledgeWhatsappLinkReview).not.toHaveBeenCalled();
      await button(wrapper, 'CANCEL').trigger('click');
      expect(wrapper.find('[role=group]').exists()).toBe(false);
      wrapper.unmount();
    }
  );

  it.each([
    ['RECHECK', 'recheckWhatsappLinkReview', 'RECHECK_SUCCESS'],
    ['ACKNOWLEDGE', 'acknowledgeWhatsappLinkReview', 'ACKNOWLEDGE_SUCCESS'],
  ])(
    'confirms %s with the observed version, then refreshes without sending',
    async (action, method, success) => {
      const wrapper = mount(WhatsappUnifiedReviews, options);
      await flushPromises();
      await button(wrapper, action).trigger('click');
      await button(wrapper, 'CONFIRM').trigger('click');
      await flushPromises();
      expect(Inboxes[method]).toHaveBeenCalledExactlyOnceWith(
        1,
        item.id,
        item.version
      );
      expect(Inboxes.getWhatsappLinkReviews).toHaveBeenCalledTimes(2);
      expect(wrapper.text()).toContain(`WHATSAPP_UNIFIED.REVIEWS.${success}`);
      expect(wrapper.find('[role=group]').exists()).toBe(false);
      wrapper.unmount();
    }
  );

  it('prevents repeated clicks while the action is in flight', async () => {
    let finish;
    Inboxes.recheckWhatsappLinkReview.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = mount(WhatsappUnifiedReviews, options);
    await flushPromises();
    await button(wrapper, 'RECHECK').trigger('click');
    await button(wrapper, 'CONFIRM').trigger('click');
    expect(button(wrapper, 'CONFIRM').element.disabled).toBe(true);
    expect(
      wrapper.findAll('select').every(select => select.element.disabled)
    ).toBe(true);
    await button(wrapper, 'CONFIRM').trigger('click');
    expect(Inboxes.recheckWhatsappLinkReview).toHaveBeenCalledTimes(1);
    finish({ data: { item } });
    await flushPromises();
    wrapper.unmount();
  });

  it('refreshes and notifies on stale revision without retrying the action', async () => {
    Inboxes.recheckWhatsappLinkReview.mockRejectedValue({
      response: { status: 409, data: { error: 'review_changed' } },
    });
    const wrapper = mount(WhatsappUnifiedReviews, options);
    await flushPromises();
    await button(wrapper, 'RECHECK').trigger('click');
    await button(wrapper, 'CONFIRM').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('WHATSAPP_UNIFIED.REVIEWS.CHANGED');
    expect(Inboxes.getWhatsappLinkReviews).toHaveBeenCalledTimes(2);
    expect(Inboxes.recheckWhatsappLinkReview).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[role=group]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('shows a safe error, never raw server details or an automatic resend', async () => {
    Inboxes.acknowledgeWhatsappLinkReview.mockRejectedValue({
      response: { status: 500, data: { error: 'SECRET_SERVER_DETAIL' } },
    });
    const wrapper = mount(WhatsappUnifiedReviews, options);
    await flushPromises();
    await button(wrapper, 'ACKNOWLEDGE').trigger('click');
    await button(wrapper, 'CONFIRM').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role=alert]').text()).toContain(
      'WHATSAPP_UNIFIED.REVIEWS.ACTION_ERROR'
    );
    expect(wrapper.text()).not.toContain('SECRET_SERVER_DETAIL');
    expect(Inboxes.acknowledgeWhatsappLinkReview).toHaveBeenCalledTimes(1);
    expect(Inboxes.recheckWhatsappLinkReview).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('supports refresh after a load failure and empty results', async () => {
    Inboxes.getWhatsappLinkReviews.mockRejectedValueOnce(
      new Error('SECRET_ERROR')
    );
    const wrapper = mount(WhatsappUnifiedReviews, options);
    await flushPromises();
    expect(wrapper.find('[role=alert]').text()).toContain(
      'WHATSAPP_UNIFIED.REVIEWS.LOAD_ERROR'
    );
    expect(wrapper.text()).not.toContain('SECRET_ERROR');
    Inboxes.getWhatsappLinkReviews.mockResolvedValue({
      data: { items: [], meta: { page: 1, total: 0, total_pages: 0 } },
    });
    await button(wrapper, 'REFRESH').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('WHATSAPP_UNIFIED.REVIEWS.EMPTY');
    expect(wrapper.find('[role=alert]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('paginates and resets page and confirmation when filters change', async () => {
    Inboxes.getWhatsappLinkReviews.mockResolvedValue({
      data: { ...response.data, meta: { page: 1, total: 21, total_pages: 2 } },
    });
    const wrapper = mount(WhatsappUnifiedReviews, options);
    await flushPromises();
    expect(button(wrapper, 'PREVIOUS').element.disabled).toBe(true);
    await button(wrapper, 'NEXT').trigger('click');
    await flushPromises();
    expect(Inboxes.getWhatsappLinkReviews).toHaveBeenLastCalledWith(1, {
      page: 2,
      kind: 'event',
      status: 'open',
    });
    await button(wrapper, 'RECHECK').trigger('click');
    await wrapper.findAll('select')[0].setValue('media');
    await flushPromises();
    expect(Inboxes.getWhatsappLinkReviews).toHaveBeenLastCalledWith(1, {
      page: 1,
      kind: 'media',
      status: 'open',
    });
    expect(wrapper.find('[role=group]').exists()).toBe(false);
    await wrapper.findAll('select')[1].setValue('all');
    await flushPromises();
    expect(Inboxes.getWhatsappLinkReviews).toHaveBeenLastCalledWith(1, {
      page: 1,
      kind: 'media',
      status: 'all',
    });
    wrapper.unmount();
  });

  it('discards a late response from the previous filter', async () => {
    let finish;
    Inboxes.getWhatsappLinkReviews.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = mount(WhatsappUnifiedReviews, options);
    await wrapper.findAll('select')[0].setValue('delivery');
    await flushPromises();
    finish({
      data: {
        items: [{ ...item, id: 'event-stale', original_id: 'STALE_ORIGINAL' }],
        meta: response.data.meta,
      },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('STALE_ORIGINAL');
    wrapper.unmount();
  });

  it('shows a disabled-link notice and historical read-only records without rechecking', async () => {
    Inboxes.getWhatsappLinkReviews.mockResolvedValue({
      data: {
        ...response.data,
        items: [{ ...item, actions: { recheck: true, acknowledge: false } }],
      },
    });
    const wrapper = mount(WhatsappUnifiedReviews, {
      ...options,
      props: { inboxId: 1, linkEnabled: false },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('WHATSAPP_UNIFIED.REVIEWS.DISABLED_LINK');
    expect(wrapper.text()).toContain('WHATSAPP_UNIFIED.REVIEWS.READ_ONLY');
    expect(button(wrapper, 'RECHECK')).toBeUndefined();
    expect(button(wrapper, 'ACKNOWLEDGE')).toBeUndefined();
    wrapper.unmount();
  });

  it('does not reinterpret uncertain delivery as successful after acknowledgement', async () => {
    const delivery = {
      ...item,
      id: 'delivery-45',
      kind: 'delivery',
      state: 'uncertain',
      reason: 'uncertain_delivery',
      actions: { recheck: false, acknowledge: true },
    };
    Inboxes.getWhatsappLinkReviews.mockResolvedValue({
      data: { ...response.data, items: [delivery] },
    });
    const wrapper = mount(WhatsappUnifiedReviews, options);
    await flushPromises();
    expect(wrapper.text()).toContain(
      'WHATSAPP_UNIFIED.REVIEWS.DELIVERY_WARNING'
    );
    expect(button(wrapper, 'RECHECK')).toBeUndefined();
    await button(wrapper, 'ACKNOWLEDGE').trigger('click');
    await button(wrapper, 'CONFIRM').trigger('click');
    await flushPromises();
    expect(Inboxes.acknowledgeWhatsappLinkReview).toHaveBeenCalledWith(
      1,
      'delivery-45',
      item.version
    );
    expect(wrapper.text()).toContain(
      'WHATSAPP_UNIFIED.REVIEWS.STATES.uncertain'
    );
    wrapper.unmount();
  });

  it('lists quarantined reservations with acknowledgement only, never automatic recheck', async () => {
    const reservation = {
      ...item,
      id: 'reservation-123',
      kind: 'reservation',
      reason: 'reservation_without_message',
      message_id: null,
      conversation_id: null,
      conversation_display_id: null,
      actions: { recheck: false, acknowledge: true },
    };
    Inboxes.getWhatsappLinkReviews.mockResolvedValue({
      data: { ...response.data, items: [reservation] },
    });
    const wrapper = mount(WhatsappUnifiedReviews, options);
    await flushPromises();
    await wrapper.findAll('select')[0].setValue('reservation');
    await flushPromises();
    expect(Inboxes.getWhatsappLinkReviews).toHaveBeenLastCalledWith(1, {
      page: 1,
      kind: 'reservation',
      status: 'open',
    });
    expect(wrapper.text()).toContain(
      'WHATSAPP_UNIFIED.REVIEWS.KINDS.reservation'
    );
    expect(wrapper.text()).toContain(
      'WHATSAPP_UNIFIED.REVIEWS.REASONS.reservation_without_message'
    );
    expect(button(wrapper, 'RECHECK')).toBeUndefined();
    expect(wrapper.findComponent({ name: 'RouterLink' }).exists()).toBe(false);
    await button(wrapper, 'ACKNOWLEDGE').trigger('click');
    expect(Inboxes.acknowledgeWhatsappLinkReview).not.toHaveBeenCalled();
    await button(wrapper, 'CONFIRM').trigger('click');
    await flushPromises();
    expect(Inboxes.acknowledgeWhatsappLinkReview).toHaveBeenCalledWith(
      1,
      'reservation-123',
      item.version
    );
    expect(Inboxes.recheckWhatsappLinkReview).not.toHaveBeenCalled();
    expect(
      ptBR.WHATSAPP_UNIFIED.REVIEWS.REASONS.reservation_without_message
    ).toContain('não há reprocessamento seguro automático');
    wrapper.unmount();
  });

  it('never offers recheck for a reservation even with an inconsistent action hint', async () => {
    Inboxes.getWhatsappLinkReviews.mockResolvedValue({
      data: {
        ...response.data,
        items: [
          {
            ...item,
            id: 'reservation-123',
            kind: 'reservation',
            actions: { recheck: true, acknowledge: false },
          },
        ],
      },
    });
    const wrapper = mount(WhatsappUnifiedReviews, options);
    await flushPromises();
    expect(button(wrapper, 'RECHECK')).toBeUndefined();
    expect(wrapper.text()).toContain('WHATSAPP_UNIFIED.REVIEWS.READ_ONLY');
    wrapper.unmount();
  });

  it('escapes opaque identifiers instead of rendering their markup', async () => {
    Inboxes.getWhatsappLinkReviews.mockResolvedValue({
      data: {
        ...response.data,
        items: [{ ...item, original_id: '<img src=x onerror=alert(1)>' }],
      },
    });
    const wrapper = mount(WhatsappUnifiedReviews, options);
    await flushPromises();
    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.text()).toContain('<img src=x onerror=alert(1)>');
    wrapper.unmount();
  });

  it.each([320, 360, 390, 412, 430, 1280])(
    'uses bounded wrapping controls for long identifiers at %s',
    async width => {
      window.innerWidth = width;
      Inboxes.getWhatsappLinkReviews.mockResolvedValue({
        data: {
          ...response.data,
          items: [{ ...item, original_id: 'opaque'.repeat(100) }],
        },
      });
      const wrapper = mount(WhatsappUnifiedReviews, options);
      await flushPromises();
      expect(wrapper.classes()).toContain('min-w-0');
      wrapper
        .findAll('select')
        .forEach(select => expect(select.classes()).toContain('min-w-0'));
      expect(wrapper.find('details dd').classes()).toContain('break-all');
      expect(wrapper.find('h5').classes()).toContain(
        '[overflow-wrap:anywhere]'
      );
      expect(wrapper.find('.sm\\:flex-row').exists()).toBe(true);
      wrapper.unmount();
    }
  );

  it('provides matching translated review fields, filters, states and action labels', () => {
    const english = en.WHATSAPP_UNIFIED.REVIEWS;
    const portuguese = ptBR.WHATSAPP_UNIFIED.REVIEWS;
    expect(Object.keys(portuguese).sort()).toEqual(Object.keys(english).sort());
    ['FIELDS', 'KINDS', 'STATUSES', 'STATES', 'REASONS', 'GUIDANCE'].forEach(
      section => {
        expect(Object.keys(portuguese[section]).sort()).toEqual(
          Object.keys(english[section]).sort()
        );
      }
    );
    expect(portuguese.NO_RESEND).toContain('nunca reenviam');
    expect(portuguese.ACKNOWLEDGE_SUCCESS).toContain('não confirma a entrega');
  });

  it.each([en, ptBR])(
    'distinguishes file availability, trust, identity conflicts and uncertain sends in each locale',
    locale => {
      const reviews = locale.WHATSAPP_UNIFIED.REVIEWS;
      expect(Object.keys(reviews.GUIDANCE).sort()).toEqual(
        Object.keys(reviews.REASONS).sort()
      );
      if (locale === ptBR) {
        expect(reviews.HELP).toContain('Não é uma fila de aprovação');
        expect(reviews.GUIDANCE.correlation_conflict).toContain(
          'remetente ou direção'
        );
        expect(reviews.GUIDANCE.untrusted_mapping).toContain(
          'não tem evidências confiáveis'
        );
        expect(reviews.GUIDANCE.principal_unavailable).toContain(
          'não significa que o canal está offline'
        );
        expect(reviews.GUIDANCE.delivery_confirmation_uncertain).toContain(
          'não reenvie automaticamente'
        );
        expect(reviews.RECHECK_HELP).toContain('Não garante correção');
        expect(reviews.ACKNOWLEDGE_HELP).toContain('não corrige a causa');
      } else {
        expect(reviews.HELP).toContain('not an approval queue');
        expect(reviews.GUIDANCE.correlation_conflict).toContain(
          'sender or direction'
        );
        expect(reviews.GUIDANCE.untrusted_mapping).toContain(
          'does not yet have trustworthy evidence'
        );
        expect(reviews.GUIDANCE.principal_unavailable).toContain(
          'does not mean the channel is offline'
        );
        expect(reviews.GUIDANCE.delivery_confirmation_uncertain).toContain(
          'do not resend automatically'
        );
        expect(reviews.RECHECK_HELP).toContain('does not guarantee a fix');
        expect(reviews.ACKNOWLEDGE_HELP).toContain('fix the cause');
      }
    }
  );
});
