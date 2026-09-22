import { shallowMount } from '@vue/test-utils';
import ContactSelector from './ContactSelector.vue';
import TagInput from 'dashboard/components-next/taginput/TagInput.vue';
import Button from 'dashboard/components-next/button/Button.vue';

describe('direct recipient confirmation', () => {
  it('confirms a normalized phone without creating a contact first', async () => {
    const wrapper = shallowMount(ContactSelector, {
      props: {
        contacts: [],
        showContactsDropdown: false,
        isLoading: false,
        isCreatingContact: false,
        showInboxesDropdown: false,
      },
    });
    await wrapper.findComponent(TagInput).vm.$emit('input', '66996222471');
    expect(wrapper.findComponent(Button).exists()).toBe(true);
    await wrapper.findComponent(Button).vm.$emit('click');
    expect(wrapper.emitted('setSelectedContact')[0][0]).toEqual({
      action: 'direct',
      recipient: { phone_number: '+5566996222471' },
    });
  });

  it('does not offer confirmation for an invalid number', async () => {
    const wrapper = shallowMount(ContactSelector, {
      props: {
        contacts: [],
        showContactsDropdown: false,
        isLoading: false,
        isCreatingContact: false,
        showInboxesDropdown: false,
      },
    });
    await wrapper.findComponent(TagInput).vm.$emit('input', '123');
    expect(wrapper.findComponent(Button).exists()).toBe(false);
  });
});
