import { flushPromises, mount } from '@vue/test-utils';
import ReportsAPI from 'dashboard/api/reports';
import PartnerInboxReports from '../PartnerInboxReports.vue';

vi.mock('dashboard/api/reports', () => ({
  default: { getPartnerInboxes: vi.fn() },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('../components/ReportHeader.vue', () => ({
  default: { template: '<header />' },
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
    vi.clearAllMocks();
    ReportsAPI.getPartnerInboxes.mockResolvedValue({ data });
  });

  it('defaults to 30 days and keeps unknown rates blank', async () => {
    const wrapper = mount(PartnerInboxReports, {
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    expect(wrapper.find('select').element.value).toBe('30');
    const params = ReportsAPI.getPartnerInboxes.mock.calls[0][0];
    expect((Date.parse(params.to) - Date.parse(params.from)) / 86400000).toBe(
      29
    );
    expect(params.service_rate).toBe('');
    expect(wrapper.text()).toContain('PARTNER_REPORT.NO_TIMEZONE');
  });

  it('submits an explicit zero without treating it as an unknown rate', async () => {
    const wrapper = mount(PartnerInboxReports, {
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();
    await wrapper.find('input[type="number"]').setValue('0');
    await wrapper.find('input[type="text"]').setValue('America/Cuiaba');
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
    await wrapper.findAll('select')[2].setValue('3');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(ReportsAPI.getPartnerInboxes.mock.lastCall[0]).toMatchObject({
      from: '2026-10-01',
      to: '2026-10-20',
      ad_window_days: '3',
    });
  });
});
