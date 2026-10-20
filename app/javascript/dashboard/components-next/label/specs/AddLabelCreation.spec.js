import { ref } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import AddLabel from '../AddLabel.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import CreateLabel from 'dashboard/routes/dashboard/settings/labels/AddLabel.vue';

const state = vi.hoisted(() => ({ allowed: null }));
vi.mock('dashboard/composables/useLabelCreation', () => ({
  useLabelCreation: () => ({ canCreateLabels: state.allowed }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

describe('contact label creation', () => {
  beforeEach(() => { state.allowed = ref(false); });

  it('keeps ordinary label assignment available without creation permission', async () => {
    const wrapper = shallowMount(AddLabel, {
      props: { labelMenuItems: [{ label: 'existing', value: 1, action: 'contactLabel' }] },
      global: { directives: { 'on-clickaway': {} } },
    });
    await wrapper.get('button').trigger('click');
    const menu = wrapper.findComponent(DropdownMenu);
    expect(menu.props('menuItems').map(item => item.action)).toEqual(['contactLabel']);
    menu.vm.$emit('action', { action: 'contactLabel', value: 1 });
    expect(wrapper.emitted('updateLabel')[0]).toEqual([{ action: 'contactLabel', value: 1 }]);
  });

  it('allows an authorized agent to open creation with the searched name', async () => {
    state.allowed.value = true;
    const wrapper = shallowMount(AddLabel, {
      props: { labelMenuItems: [{ label: 'existing', value: 1, action: 'contactLabel' }] },
      global: {
        directives: { 'on-clickaway': {} },
        stubs: { WootModal: { props: ['show'], template: '<div v-if="show"><slot /></div>' } },
      },
    });
    await wrapper.get('button').trigger('click');
    const menu = wrapper.findComponent(DropdownMenu);
    menu.vm.$emit('search', 'new-label');
    await flushPromises();
    expect(menu.props('menuItems').map(item => item.action)).toEqual(['createLabel']);
    menu.vm.$emit('action', { action: 'createLabel', value: 'createLabel' });
    await flushPromises();
    expect(wrapper.findComponent(CreateLabel).props('prefillTitle')).toBe('new-label');
    expect(wrapper.emitted('updateLabel')).toBeUndefined();
  });
});
