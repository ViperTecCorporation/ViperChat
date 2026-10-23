import { flushPromises, mount } from '@vue/test-utils';
import ReportsAPI from 'dashboard/api/reports';
import PartnerInboxReports from '../PartnerInboxReports.vue';

vi.mock('dashboard/api/reports', () => ({
  default: {
    getPartnerInboxes: vi.fn(),
    getAdLeads: vi.fn(),
    getPartnerInboxSettings: vi.fn(),
    savePartnerInboxSettings: vi.fn(),
  },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('../components/ReportHeader.vue', () => ({
  default: { template: '<header />' },
}));
vi.mock('shared/components/charts/BarChart.vue', () => ({
  default: {
    name: 'BarChart',
    props: ['collection', 'chartOptions'],
    template: '<div class="test-chart" />',
  },
}));

const counts = {
  whatsapp_cloud: { incoming: 1, outgoing: 2, delivered: 1 },
  unoapi: { incoming: 1, outgoing: 3, delivered: 2 },
  unknown: { incoming: 0, outgoing: 0, delivered: 0 },
  unique_messages: 6,
  ad_referrals: 1,
};
const data = {
  timezone_confirmed: false,
  simulation: null,
  timezone: 'UTC',
  totals: counts,
  available_pairs: [{ id: 1, name: 'Partner', partner_name: 'Meta' }],
  pairs: [
    { id: 1, name: 'Partner', partner_name: 'Meta', enabled: true, counts },
  ],
};

describe('PartnerInboxReports', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-10-23T12:00:00Z'));
    vi.clearAllMocks();
    ReportsAPI.getPartnerInboxes.mockResolvedValue({ data });
    ReportsAPI.getAdLeads.mockResolvedValue({ data });
    ReportsAPI.getPartnerInboxSettings.mockResolvedValue({
      data: {
        service_rate: '0.035',
        utility_rate: '0.035',
        authentication_rate: '0.035',
        marketing_rate: '0.3217',
      },
    });
    ReportsAPI.savePartnerInboxSettings.mockResolvedValue({ data: {} });
  });

  afterEach(() => vi.useRealTimers());

  it('uses the standalone ad report API without showing cost controls', async () => {
    const wrapper = mount(PartnerInboxReports, {
      props: { leadsOnly: true },
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    expect(ReportsAPI.getAdLeads).toHaveBeenCalledOnce();
    expect(ReportsAPI.getPartnerInboxes).not.toHaveBeenCalled();
    expect(wrapper.findAll('input[type="number"]')).toHaveLength(0);
    expect(wrapper.text()).toContain('PARTNER_REPORT.AD_LEADS');
  });

  it('preserves saved blanks but lets the operator explicitly restore the Brazil reference without auto-saving', async () => {
    ReportsAPI.getPartnerInboxSettings.mockResolvedValue({
      data: {
        service_rate: '',
        utility_rate: '',
        marketing_rate: '',
        authentication_rate: '',
      },
    });
    const wrapper = mount(PartnerInboxReports, {
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    expect(wrapper.find('input[type="number"]').element.value).toBe('');
    await wrapper.findAll('button[type="button"]')[1].trigger('click');
    expect(
      wrapper.findAll('input[type="number"]').map(input => input.element.value)
    ).toEqual(['0.035', '0.035', '0.3217', '0.035']);
    expect(ReportsAPI.savePartnerInboxSettings).not.toHaveBeenCalled();
  });

  it('defaults to the current calendar month and loads suggested BRL rates', async () => {
    const wrapper = mount(PartnerInboxReports, {
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    expect(wrapper.find('select').element.value).toBe('current_month');
    const params = ReportsAPI.getPartnerInboxes.mock.calls[0][0];
    expect(params).toMatchObject({ from: '2026-10-01', to: '2026-10-23' });
    expect(params).toMatchObject({
      service_rate: '0.035',
      utility_rate: '0.035',
      authentication_rate: '0.035',
      marketing_rate: '0.3217',
    });
    expect(params.timezone).toBe('UTC');
  });

  it('renders comparative charts and labels avoided cost as an estimate', async () => {
    ReportsAPI.getPartnerInboxes.mockResolvedValue({
      data: {
        ...data,
        daily: [{ date: '2026-10-23', counts }],
        simulation: {
          estimated_cost: '35.0',
          months: [],
          comparison: {
            all_meta_cost: '140.0',
            avoided_meta_cost: '105.0',
            avoided_percent: '75.0',
            unclassified: 2,
            unpriced: 1,
          },
        },
      },
    });
    const wrapper = mount(PartnerInboxReports, {
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    const charts = wrapper.findAllComponents({ name: 'BarChart' });
    expect(wrapper.findAll('.test-chart')).toHaveLength(2);
    expect(wrapper.text()).toContain('PARTNER_REPORT.AVOIDED_COST');
    expect(wrapper.text()).toContain('75.0%');
    expect(charts[0].props('collection').datasets.map(row => row.data)).toEqual(
      [[2], [3], [0]]
    );
    expect(charts[1].props('collection').datasets[0].data).toEqual([35, 140]);
  });

  it('uses the account timezone at month rollover and allows selecting a different timezone', async () => {
    vi.setSystemTime(new Date('2026-11-01T01:00:00Z'));
    ReportsAPI.getPartnerInboxSettings.mockResolvedValue({
      data: { account_timezone: 'America/Cuiaba' },
    });
    const wrapper = mount(PartnerInboxReports, {
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    expect(ReportsAPI.getPartnerInboxes.mock.lastCall[0]).toMatchObject({
      from: '2026-10-01',
      to: '2026-10-31',
    });
    await wrapper.find('[data-testid="report-timezone"]').setValue('UTC');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(ReportsAPI.getPartnerInboxes.mock.lastCall[0]).toMatchObject({
      from: '2026-11-01',
      to: '2026-11-01',
    });
    await wrapper.find('[data-testid="report-timezone"]').setValue('');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(ReportsAPI.getPartnerInboxes.mock.lastCall[0]).toMatchObject({
      from: '2026-10-01',
      to: '2026-10-31',
      timezone: 'America/Cuiaba',
    });
  });

  it('keeps rolling 30-day ranges available separately from the current month', async () => {
    const wrapper = mount(PartnerInboxReports, {
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    await wrapper.find('select').setValue('30');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(ReportsAPI.getPartnerInboxes.mock.lastCall[0]).toMatchObject({
      from: '2026-09-24',
      to: '2026-10-23',
    });
  });

  it('submits an explicit zero without treating it as an unknown rate', async () => {
    const wrapper = mount(PartnerInboxReports, {
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    await wrapper.find('input[type="number"]').setValue('0');
    await wrapper
      .find('[data-testid="report-timezone"]')
      .setValue('America/Cuiaba');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(ReportsAPI.getPartnerInboxes.mock.lastCall[0]).toMatchObject({
      service_rate: 0,
      timezone: 'America/Cuiaba',
    });
  });

  it('shows validation errors and removes the stale report', async () => {
    const wrapper = mount(PartnerInboxReports, {
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    ReportsAPI.getPartnerInboxes.mockRejectedValue({
      response: { data: { error: 'invalid_timezone' } },
    });
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').text()).toBe(
      'PARTNER_REPORT.ERRORS.invalid_timezone'
    );
    expect(wrapper.text()).not.toContain('PARTNER_REPORT.UNIQUE');
  });

  it('preserves custom calendar dates and the selected ad window', async () => {
    const wrapper = mount(PartnerInboxReports, {
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    await wrapper.find('select').setValue('custom');
    const dates = wrapper.findAll('input[type="date"]');
    await dates[0].setValue('2026-10-01');
    await dates[1].setValue('2026-10-20');
    await wrapper.findAll('select')[3].setValue('3');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(ReportsAPI.getPartnerInboxes.mock.lastCall[0]).toMatchObject({
      from: '2026-10-01',
      to: '2026-10-20',
      ad_window_days: '3',
    });
  });

  it('loads saved rates before calculating and allows editing and saving again', async () => {
    ReportsAPI.getPartnerInboxSettings.mockResolvedValue({
      data: {
        service_rate: '0.04',
        utility_rate: 0,
        marketing_rate: '',
        authentication_rate: '',
        timezone: 'America/Cuiaba',
        currency: 'USD',
        ad_window_days: 3,
      },
    });
    const wrapper = mount(PartnerInboxReports, {
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    expect(ReportsAPI.getPartnerInboxes.mock.lastCall[0]).toMatchObject({
      service_rate: '0.04',
      utility_rate: 0,
      timezone: 'America/Cuiaba',
      ad_window_days: '3',
    });
    await wrapper.find('input[type="number"]').setValue('0.08');
    await wrapper.find('button[type="button"]').trigger('click');
    await flushPromises();
    expect(ReportsAPI.savePartnerInboxSettings).toHaveBeenCalledWith({
      service_rate: 0.08,
      utility_rate: 0,
      marketing_rate: '',
      authentication_rate: '',
      timezone: 'America/Cuiaba',
      currency: 'USD',
      ad_window_days: '3',
    });
    expect(wrapper.text()).toContain('PARTNER_REPORT.SETTINGS_SAVED');
    await wrapper.find('input[type="number"]').setValue('');
    await wrapper.find('button[type="button"]').trigger('click');
    await flushPromises();
    expect(
      ReportsAPI.savePartnerInboxSettings.mock.lastCall[0].service_rate
    ).toBe('');
  });

  it('keeps edits and reports a failed save without claiming success', async () => {
    ReportsAPI.savePartnerInboxSettings.mockRejectedValue(new Error('network'));
    const wrapper = mount(PartnerInboxReports, {
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    await wrapper.find('input[type="number"]').setValue('0.04');
    await wrapper.find('button[type="button"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('PARTNER_REPORT.SETTINGS_SAVE_ERROR');
    expect(wrapper.text()).not.toContain('PARTNER_REPORT.SETTINGS_SAVED');
    expect(wrapper.find('input[type="number"]').element.value).toBe('0.04');
  });

  it('does not overwrite settings when loading them fails', async () => {
    ReportsAPI.getPartnerInboxSettings.mockRejectedValue(new Error('network'));
    const wrapper = mount(PartnerInboxReports, {
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('PARTNER_REPORT.SETTINGS_LOAD_ERROR');
    expect(wrapper.find('button[type="button"]').element.disabled).toBe(true);
    expect(ReportsAPI.savePartnerInboxSettings).not.toHaveBeenCalled();
  });
});
