import { mount } from '@vue/test-utils';
import HistoryPeriod from './HistoryPeriod.vue';

describe('Gmail history period', () => {
  it('defaults to new mail only and offers no option beyond twelve months', () => {
    const wrapper = mount(HistoryPeriod, {
      global: { mocks: { $t: key => key } },
    });
    expect(wrapper.find('select').element.value).toBe('none');
    expect(
      wrapper.findAll('option').map(option => option.attributes('value'))
    ).toEqual(['none', '7d', '30d', '3m', '6m', '12m']);
    wrapper.unmount();
  });
  it('emits the chosen period and disables editing during authorization', async () => {
    const wrapper = mount(HistoryPeriod, {
      global: { mocks: { $t: key => key } },
    });
    await wrapper.find('select').setValue('12m');
    expect(wrapper.emitted('update:modelValue')).toEqual([['12m']]);
    await wrapper.setProps({ disabled: true });
    expect(wrapper.find('select').attributes('disabled')).toBeDefined();
    wrapper.unmount();
  });
});
