import { mount } from '@vue/test-utils';
import AdLeadsTable from '../components/AdLeadsTable.vue';

describe('AdLeadsTable', () => {
  const leads = Array.from({ length: 12 }, (_, i) => ({
    contact_id: i + 1,
    message_id: i + 100,
    contact_name: `SYNTHETIC Lead ${i + 1}`,
    contact_phone: `550000000${i}`,
    business_phone: '550000000000',
    inbox_id: (i % 2) + 1,
    inbox_name: `Inbox ${(i % 2) + 1}`,
    ad_source_id: i % 2 ? 'ad-b' : 'ad-a',
    provider: 'whatsapp_cloud',
    received_providers: ['whatsapp_cloud'],
    state: i % 2 ? 'no_eligible_response' : 'expired',
    free_meta_messages: 10,
    window_days: i % 2 ? 0 : 7,
    received_at: '2026-10-01T10:00:00Z',
    window_start: i % 2 ? null : '2026-10-01T11:00:00Z',
    window_end: i % 2 ? null : '2026-10-08T11:00:00Z',
    exempt_days_elapsed: i % 2 ? 0 : 7,
  }));

  it('paginates and combines contact, ad, inbox, provider and window filters', async () => {
    const wrapper = mount(AdLeadsTable, {
      props: { leads },
      global: { mocks: { $t: key => key } },
    });
    expect(wrapper.findAll('article')).toHaveLength(10);
    await wrapper.findAll('button')[1].trigger('click');
    expect(wrapper.findAll('article')).toHaveLength(2);
    await wrapper.findAll('input')[1].setValue('ad-a');
    expect(wrapper.findAll('article')).toHaveLength(6);
    await wrapper.findAll('select')[0].setValue('whatsapp_cloud');
    await wrapper.findAll('select')[1].setValue('1');
    await wrapper.findAll('select')[2].setValue('expired');
    expect(wrapper.findAll('article')).toHaveLength(6);
    await wrapper.findAll('input')[0].setValue('Lead 3');
    expect(wrapper.findAll('article')).toHaveLength(1);
    expect(wrapper.text()).toContain('SYNTHETIC Lead 3');
    await wrapper.findAll('select')[2].setValue('no_eligible_response');
    expect(wrapper.findAll('article')).toHaveLength(0);
  });
});
