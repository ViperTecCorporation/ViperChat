import { shallowMount } from '@vue/test-utils';
import ComboBox from '../ComboBox.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

describe('ComboBox accent-insensitive filtering', () => {
  it('finds an accented label and emits its unchanged value', async () => {
    const options = [
      { label: 'João — Manutenção', value: 42 },
      { label: 'Maria', value: 43 },
    ];
    const wrapper = shallowMount(ComboBox, {
      props: { options },
      global: { renderStubDefaultSlot: true },
    });
    const dropdown = wrapper.findComponent({ name: 'ComboBoxDropdown' });
    dropdown.vm.$emit('update:searchValue', 'joao');
    await wrapper.vm.$nextTick();
    expect(dropdown.props('options')).toEqual([options[0]]);
    dropdown.vm.$emit('select', options[0]);
    expect(wrapper.emitted('update:modelValue')).toEqual([[42]]);
    expect(options[0].label).toBe('João — Manutenção');
  });

  it('does not refilter server results when useApiResults is enabled', async () => {
    const options = [{ label: 'Cláudia', value: 42 }];
    const wrapper = shallowMount(ComboBox, {
      props: { options, useApiResults: true },
      global: { renderStubDefaultSlot: true },
    });
    const dropdown = wrapper.findComponent({ name: 'ComboBoxDropdown' });
    dropdown.vm.$emit('update:searchValue', 'unrelated');
    await wrapper.vm.$nextTick();
    expect(dropdown.props('options')).toEqual(options);
  });
});
