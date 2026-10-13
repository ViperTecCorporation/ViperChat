import { shallowMount } from '@vue/test-utils';
import BulkActions from './Index.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

vi.mock('dashboard/composables/chatlist/useBulkActions.js', () => ({
  useBulkActions: () => ({ selectedConversations: { value: [] } }),
}));
vi.mock('dashboard/composables/store.js', () => ({
  useMapGetter: () => ({ value: () => ({ labels: [] }) }),
}));

describe('conversation bulk action bar', () => {
  it('keeps all five actions separate from the wrapping selection summary', async () => {
    const wrapper = shallowMount(BulkActions, {
      global: { stubs: { Transition: { template: '<div><slot /></div>' } } },
      props: { conversations: Array.from({ length: 25 }, (_, i) => i + 1) },
    });
    const actions = wrapper.get('[data-testid="conversation-bulk-actions"]');
    expect(actions.classes()).toContain('basis-64');
    expect(actions.element.children).toHaveLength(5);
    expect(
      wrapper.findAllComponents({ name: 'BulkLabelActions' })
    ).toHaveLength(2);
    wrapper.findComponent(NextButton).vm.$emit('click');
    expect(wrapper.emitted('selectAllConversations')).toEqual([[false]]);
    await wrapper.setProps({ conversations: [] });
    expect(wrapper.find('[data-testid="conversation-bulk-bar"]').exists()).toBe(
      false
    );
  });
});
