import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import AccountInsights from '../AccountInsights.vue';
import InboxesAPI from 'dashboard/api/inboxes';
import en from 'dashboard/i18n/locale/en/inboxMgmt.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/inboxMgmt.json';

describe('AccountInsights', () => {
  let wrapper;
  let get;
  let payload;

  beforeEach(() => {
    get = vi.fn();
    vi.stubGlobal('axios', { get });
    vi.spyOn(InboxesAPI, 'url', 'get').mockReturnValue(
      '/api/v1/accounts/9/inboxes'
    );
    payload = {
      informational_only: true,
      period: {
        days: 30,
        start: '2026-09-17T00:00:00Z',
        end: '2026-10-17T00:00:00Z',
      },
      fetched_at: '2026-10-17T12:00:00Z',
      cached_until: '2026-10-17T12:10:00Z',
      currency: 'USD',
      sections: {
        messages: {
          status: 'available',
          data: {
            data_points: [
              { sent: 12, delivered: 10 },
              { sent: 8, delivered: 0 },
            ],
          },
        },
        pricing: {
          status: 'available',
          data: {
            data: [
              {
                data_points: [
                  { volume: 12, cost: 0.5 },
                  { volume: 8, cost: 0 },
                ],
              },
            ],
          },
        },
        calls: {
          status: 'available',
          data: { data: [{ data_points: [{ count: 2, cost: 0.25 }] }] },
        },
      },
    };
  });

  afterEach(() => {
    wrapper?.unmount();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  const render = (locale = 'en') => {
    wrapper = mount(AccountInsights, {
      props: { inboxId: 4 },
      global: {
        plugins: [
          createI18n({ legacy: false, locale, messages: { en, pt_BR: ptBR } }),
        ],
        stubs: {
          ButtonV4: {
            props: ['isLoading', 'disabled'],
            template: '<button :disabled="disabled"><slot /></button>',
          },
        },
      },
    });
    return wrapper;
  };

  it('fetches once on mount and sums only actual metrics in the raw schema', async () => {
    get.mockResolvedValue({ data: payload });
    render();
    expect(wrapper.attributes('aria-busy')).toBe('true');
    expect(wrapper.get('button').attributes('disabled')).toBeDefined();
    expect(wrapper.get('[role="status"]').text()).toContain('Loading');
    await flushPromises();
    expect(get).toHaveBeenCalledExactlyOnceWith(
      '/api/v1/accounts/9/inboxes/4/insights',
      { params: { days: 30 } }
    );
    expect(
      wrapper
        .get('[data-testid="messages"]')
        .findAll('dd')
        .map(node => node.text())
    ).toEqual(['20', '10', 'Unavailable']);
    expect(
      wrapper
        .get('[data-testid="pricing"] > dl')
        .findAll('dd')
        .map(node => node.text())
    ).toEqual(['20', '$0.50', 'Unavailable', 'Unavailable', 'Unavailable']);
    expect(
      wrapper
        .get('[data-testid="calls"]')
        .findAll('dd')
        .map(node => node.text())
    ).toEqual([
      '2',
      'Unavailable',
      'Unavailable',
      'Unavailable',
      'Unavailable',
    ]);
    expect(wrapper.text()).toContain('Completed UTC days');
    expect(wrapper.text()).toContain('not an invoice');
    expect(wrapper.attributes('aria-busy')).toBe('false');
  });

  it('keeps empty, unavailable, null and partially missing metrics distinct from zero', async () => {
    payload.sections.messages.data.data_points = [
      { sent: 0, delivered: 2 },
      { sent: 0 },
    ];
    payload.sections.pricing = { status: 'unavailable', data: null };
    payload.sections.calls.data.data = [];
    get.mockResolvedValue({ data: payload });
    render();
    await flushPromises();
    expect(
      wrapper
        .get('[data-testid="messages"]')
        .findAll('dd')
        .map(node => node.text())
    ).toEqual(['0', 'Unavailable', 'Unavailable']);
    expect(
      wrapper
        .get('[data-testid="pricing"]')
        .findAll('dd')
        .every(node => node.text() === 'Unavailable')
    ).toBe(true);
    expect(
      wrapper
        .get('[data-testid="calls"]')
        .findAll('dd')
        .every(node => node.text() === 'Unavailable')
    ).toBe(true);
  });

  it('does not show known costs when currency is missing or mixed', async () => {
    payload.currency = null;
    payload.sections.pricing.data.data[0].data_points = [
      { volume: 1, cost: 1 },
    ];
    payload.sections.calls.data.data[0].data_points = [
      { count: 1, cost: 1, currency: 'USD' },
      { count: 2, cost: 2, currency: 'BRL' },
    ];
    get.mockResolvedValue({ data: payload });
    render();
    await flushPromises();
    expect(wrapper.get('[data-testid="pricing"]').findAll('dd')[1].text()).toBe(
      'Unavailable'
    );
    expect(wrapper.get('[data-testid="calls"]').findAll('dd')[1].text()).toBe(
      'Unavailable'
    );
  });

  it('formats call costs only with their own currency and translates Portuguese', async () => {
    payload.sections.calls.data.data[0].data_points[0].currency = 'BRL';
    get.mockResolvedValue({ data: payload });
    render('pt_BR');
    await flushPromises();
    expect(wrapper.text()).toContain('Indicadores da Meta');
    expect(
      wrapper.get('[data-testid="calls"]').findAll('dd')[1].text()
    ).toMatch(/R\$\s*0,25/);
    expect(
      wrapper.get('[data-testid="messages"]').findAll('dd')[2].text()
    ).toBe('Indisponível');
    expect(wrapper.text()).toContain('dias completos em UTC');
  });

  it('changes periods and inboxes, and refreshes only on explicit action', async () => {
    get.mockResolvedValue({ data: payload });
    render();
    await flushPromises();
    expect(wrapper.get('label').text()).toContain('Period');
    expect(wrapper.findAll('option').map(node => node.element.value)).toEqual([
      '7',
      '30',
      '90',
    ]);
    await wrapper.get('select').setValue('7');
    await flushPromises();
    expect(get).toHaveBeenLastCalledWith(
      '/api/v1/accounts/9/inboxes/4/insights',
      { params: { days: 7 } }
    );
    await wrapper.setProps({ inboxId: '6' });
    await flushPromises();
    expect(get).toHaveBeenLastCalledWith(
      '/api/v1/accounts/9/inboxes/6/insights',
      { params: { days: 7 } }
    );
    await wrapper.get('select').setValue('90');
    await flushPromises();
    expect(get).toHaveBeenLastCalledWith(
      '/api/v1/accounts/9/inboxes/6/insights',
      { params: { days: 90 } }
    );
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(get).toHaveBeenCalledTimes(5);
  });

  it('isolates a request error, never displays raw error details, and allows retry', async () => {
    get
      .mockRejectedValueOnce(new Error('secret upstream details'))
      .mockResolvedValueOnce({ data: payload });
    render();
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('Could not load');
    expect(wrapper.text()).not.toContain('secret');
    expect(wrapper.find('[data-testid="messages"]').exists()).toBe(false);
    expect(wrapper.get('button').text()).toBe('Try again');
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="messages"]').exists()).toBe(true);
  });

  it('ignores late responses from the previous inbox', async () => {
    let resolveFirst;
    get
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            resolveFirst = resolve;
          })
      )
      .mockResolvedValueOnce({ data: { ...payload, sections: {} } });
    render();
    await wrapper.setProps({ inboxId: 8 });
    await flushPromises();
    resolveFirst({ data: payload });
    await flushPromises();
    expect(
      wrapper
        .get('[data-testid="messages"]')
        .findAll('dd')
        .map(node => node.text())
    ).toEqual(['Unavailable', 'Unavailable', 'Unavailable']);
  });

  it('uses only explicit received fields from the separate incoming points', async () => {
    payload.sections.messages.received_status = 'available';
    payload.sections.messages.data.received_data_points = [
      { received: 3, sent: 50 },
      { received: 0, sent: 100 },
    ];
    get.mockResolvedValue({ data: payload });
    render();
    await flushPromises();
    expect(
      wrapper
        .get('[data-testid="messages"]')
        .findAll('dd')
        .map(node => node.text())
    ).toEqual(['20', '10', '3']);
    payload.sections.messages.data.received_data_points = [{ sent: 150 }];
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(
      wrapper.get('[data-testid="messages"]').findAll('dd')[2].text()
    ).toBe('Unavailable');
  });

  it('groups pricing categories and free/paid volumes only from actual pricing types', async () => {
    payload.sections.pricing.data.data = [
      {
        data_points: [
          {
            pricing_category: 'MARKETING',
            pricing_type: 'REGULAR',
            volume: 8,
            cost: 0.5,
          },
          {
            pricing_category: 'UTILITY',
            pricing_type: 'FREE_CUSTOMER_SERVICE',
            volume: 2,
            cost: 0,
          },
          {
            pricing_category: 'UTILITY',
            pricing_type: 'FREE_ENTRY_POINT',
            volume: 3,
            cost: 0,
          },
        ],
      },
    ];
    get.mockResolvedValue({ data: payload });
    render();
    await flushPromises();
    expect(
      wrapper
        .get('[data-testid="pricing"] > dl')
        .findAll('dd')
        .map(node => node.text())
    ).toEqual(['13', '$0.50', '2', '3', '8']);
    const categories = wrapper.findAll('[data-testid="pricing-category"]');
    expect(categories.map(node => node.get('h6').text())).toEqual([
      'Marketing',
      'Utility',
    ]);
    expect(categories[0].findAll('dd').map(node => node.text())).toEqual([
      '8',
      '$0.50',
    ]);
    expect(categories[1].findAll('dd').map(node => node.text())).toEqual([
      '5',
      '$0.00',
    ]);
  });

  it('leaves category costs and missing pricing types unavailable, not free', async () => {
    payload.sections.pricing.data.data[0].data_points = [
      { pricing_category: 'MARKETING', volume: 0 },
    ];
    get.mockResolvedValue({ data: payload });
    render();
    await flushPromises();
    expect(
      wrapper
        .get('[data-testid="pricing"] > dl')
        .findAll('dd')
        .map(node => node.text())
    ).toEqual([
      '0',
      'Unavailable',
      'Unavailable',
      'Unavailable',
      'Unavailable',
    ]);
    expect(
      wrapper
        .get('[data-testid="pricing-category"]')
        .findAll('dd')
        .map(node => node.text())
    ).toEqual(['0', 'Unavailable']);
  });

  it('weights call duration by count and groups only known directions', async () => {
    payload.sections.calls.data.data[0].data_points = [
      { count: 2, average_duration: 10, direction: 'BUSINESS_INITIATED' },
      { count: 6, average_duration: 30, direction: 'USER_INITIATED' },
      { count: 0, direction: 'USER_INITIATED' },
    ];
    get.mockResolvedValue({ data: payload });
    render();
    await flushPromises();
    expect(
      wrapper
        .get('[data-testid="calls"]')
        .findAll('dd')
        .map(node => node.text())
    ).toEqual(['8', 'Unavailable', '25', '2', '6']);
  });

  it.each([
    [{ count: 0, average_duration: 10 }],
    [{ count: 2 }],
    [{ average_duration: 10 }],
    [{ count: -1, average_duration: 10 }],
    [{ count: 1, average_duration: -1 }],
    [{ count: 1, average_duration: 10 }, { count: 1 }],
  ])(
    'does not invent duration from missing or invalid call metrics (%j)',
    (...points) => {
      payload.sections.calls.data.data[0].data_points = points;
      get.mockResolvedValue({ data: payload });
      render();
      return flushPromises().then(() => {
        expect(
          wrapper.get('[data-testid="calls"]').findAll('dd')[2].text()
        ).toBe('Unavailable');
      });
    }
  );

  it('keeps incoming unavailable when the backend marks the incoming query unavailable', async () => {
    payload.sections.messages.received_status = 'unavailable';
    payload.sections.messages.data.received_data_points = [{ received: 10 }];
    get.mockResolvedValue({ data: payload });
    render();
    await flushPromises();
    expect(
      wrapper.get('[data-testid="messages"]').findAll('dd')[2].text()
    ).toBe('Unavailable');
  });

  it('clears the previous period while loading and ignores its late error', async () => {
    let rejectPrevious;
    get
      .mockResolvedValueOnce({ data: payload })
      .mockImplementationOnce(
        () =>
          new Promise((resolve, reject) => {
            rejectPrevious = reject;
          })
      )
      .mockResolvedValueOnce({ data: payload });
    render();
    await flushPromises();
    await wrapper.get('select').setValue('7');
    expect(wrapper.find('[data-testid="messages"]').exists()).toBe(false);
    expect(wrapper.find('[role="status"]').exists()).toBe(true);
    await wrapper.get('select').setValue('90');
    await flushPromises();
    rejectPrevious(new Error('outdated period failed'));
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(wrapper.attributes('aria-busy')).toBe('false');
    expect(
      wrapper.get('[data-testid="messages"]').findAll('dd')[0].text()
    ).toBe('20');
  });
});
