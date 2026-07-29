import { shallowMount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import UnoapiContactSync from '../UnoapiContactSync.vue';
import SwitchControl from 'dashboard/components-next/switch/Switch.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}:${JSON.stringify(params)}` : key),
  }),
}));

describe('UnoapiContactSync', () => {
  const inbox = {
    contact_sync_status: 'completed',
    contact_sync_processed_count: 198,
    contact_sync_failed_count: 2,
    contact_sync_total_count: 200,
    contact_sync_completed_at: '2026-07-25T12:00:00Z',
    contact_sync_next_run_at: '2026-07-25T15:00:00Z',
    contact_sync_error: '2 contact(s) failed',
  };

  it('renders operational synchronization state and progress', () => {
    const wrapper = shallowMount(UnoapiContactSync, {
      props: { modelValue: true, inbox },
    });

    expect(wrapper.text()).toContain(
      'INBOX_MGMT.ADD.WHATSAPP.CONTACT_SYNC.STATUS.COMPLETED'
    );
    expect(wrapper.text()).toContain('"progress":"198/200"');
    expect(wrapper.text()).toContain('"failed":2');
    expect(wrapper.text()).toContain('2 contact(s) failed');
  });

  it('emits the local flag change', () => {
    const wrapper = shallowMount(UnoapiContactSync, {
      props: { modelValue: false, inbox },
    });

    wrapper.findComponent(SwitchControl).vm.$emit('update:modelValue', true);

    expect(wrapper.emitted('update:modelValue')).toEqual([[true]]);
  });

  it('keeps contact export inbox-scoped and dependent on synchronization', () => {
    const wrapper = shallowMount(UnoapiContactSync, {
      props: { modelValue: true, exportEnabled: false, inbox },
    });
    const switches = wrapper.findAllComponents(SwitchControl);

    expect(switches).toHaveLength(2);
    switches[1].vm.$emit('update:modelValue', true);
    expect(wrapper.emitted('update:exportEnabled')).toEqual([[true]]);

    switches[0].vm.$emit('update:modelValue', false);
    expect(wrapper.emitted('update:exportEnabled')).toEqual([[true], [false]]);
  });
});
