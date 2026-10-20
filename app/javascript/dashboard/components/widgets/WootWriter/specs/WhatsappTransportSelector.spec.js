import { mount } from '@vue/test-utils';
import WhatsappTransportSelector from '../WhatsappTransportSelector.vue';

const transports = [
  { provider: 'unoapi', label: 'ViperConnect', can_reply: true },
  { provider: 'whatsapp_cloud', label: 'Meta', can_reply: false },
];

describe('WhatsappTransportSelector availability status', () => {
  it('keeps option labels short and displays the unavailable status outside the select', () => {
    const wrapper = mount(WhatsappTransportSelector, {
      props: { modelValue: 'whatsapp_cloud', transports },
      global: { mocks: { $t: key => key } },
    });
    expect(wrapper.findAll('option').map(option => option.text())).toEqual([
      'ViperConnect',
      'Meta',
    ]);
    expect(wrapper.get('select').find('[role="status"]').exists()).toBe(false);
    const status = wrapper.get('[role="status"]');
    expect(status.text()).toBe('WHATSAPP_UNIFIED.UNAVAILABLE');
    expect(status.element.parentElement).toBe(wrapper.element);
    expect(status.classes()).toEqual(
      expect.arrayContaining(['w-full', 'min-w-0', 'break-words'])
    );
    wrapper.unmount();
  });

  it('shows availability for the selected provider only and reacts to selection changes', async () => {
    const wrapper = mount(WhatsappTransportSelector, {
      props: { modelValue: 'unoapi', transports },
      global: { mocks: { $t: key => key } },
    });
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
    await wrapper.setProps({ modelValue: 'whatsapp_cloud' });
    expect(wrapper.find('[role="status"]').exists()).toBe(true);
    await wrapper.setProps({ modelValue: 'unoapi' });
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('does not call unknown availability unavailable', () => {
    const wrapper = mount(WhatsappTransportSelector, {
      props: {
        modelValue: 'whatsapp_cloud',
        transports: [{ provider: 'whatsapp_cloud', label: 'Meta' }],
      },
      global: { mocks: { $t: key => key } },
    });
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('emits explicit selection without changing it when availability updates', async () => {
    const wrapper = mount(WhatsappTransportSelector, {
      props: { modelValue: 'unoapi', transports },
      global: { mocks: { $t: key => key } },
    });
    await wrapper.get('select').setValue('whatsapp_cloud');
    expect(wrapper.emitted('update:modelValue')).toEqual([['whatsapp_cloud']]);
    await wrapper.setProps({
      modelValue: 'whatsapp_cloud',
      transports: transports.map(transport => ({
        ...transport,
        can_reply: true,
      })),
    });
    expect(wrapper.get('select').element.value).toBe('whatsapp_cloud');
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
    expect(wrapper.emitted('update:modelValue')).toHaveLength(1);
    wrapper.unmount();
  });

  it('keeps the disabled control and its status readable', () => {
    const wrapper = mount(WhatsappTransportSelector, {
      props: { modelValue: 'whatsapp_cloud', transports, disabled: true },
      global: { mocks: { $t: key => key } },
    });
    expect(wrapper.get('select').element.disabled).toBe(true);
    expect(wrapper.get('[role="status"]').text()).toBe(
      'WHATSAPP_UNIFIED.UNAVAILABLE'
    );
    wrapper.unmount();
  });
});
