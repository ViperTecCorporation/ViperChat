import { shallowMount } from '@vue/test-utils';
import ConditionRow from './ConditionRow.vue';
import FilterSelect from './inputs/FilterSelect.vue';
import MultiSelect from './inputs/MultiSelect.vue';
import Button from 'next/button/Button.vue';

describe('ConditionRow', () => {
  const props = {
    attributeKey: 'status',
    filterOperator: 'equal_to',
    values: [{ id: 'open', name: 'Abertas' }],
    filterTypes: [
      {
        attributeKey: 'status',
        value: 'status',
        label: 'Status',
        inputType: 'multiSelect',
        options: [{ id: 'open', name: 'Abertas' }],
        filterOperators: [
          { value: 'equal_to', label: 'Igual a', hasInput: true },
        ],
      },
    ],
  };

  it('stacks controls on mobile while retaining the desktop row', () => {
    const wrapper = shallowMount(ConditionRow, { props });
    const row = wrapper.get('[data-testid="filter-condition-row"]');
    expect(row.classes()).toEqual(
      expect.arrayContaining(['grid', 'grid-cols-1', 'min-w-0', 'lg:flex'])
    );
    expect(wrapper.findAllComponents(FilterSelect)).toHaveLength(2);
    expect(wrapper.getComponent(MultiSelect).props('modelValue')).toEqual(
      props.values
    );
    wrapper.getComponent(Button).vm.$emit('click', new MouseEvent('click'));
    expect(wrapper.emitted('remove')).toHaveLength(1);
  });

  it('keeps the query operator and value changes for additional conditions', () => {
    const wrapper = shallowMount(ConditionRow, {
      props: { ...props, showQueryOperator: true, queryOperator: 'and' },
    });
    const selectors = wrapper.findAllComponents(FilterSelect);
    expect(selectors).toHaveLength(3);
    selectors[0].vm.$emit('update:modelValue', 'or');
    expect(wrapper.emitted('update:queryOperator')[0]).toEqual(['or']);
    wrapper.getComponent(MultiSelect).vm.$emit('update:modelValue', []);
    expect(wrapper.emitted('update:values')[0]).toEqual([[]]);
  });
});
