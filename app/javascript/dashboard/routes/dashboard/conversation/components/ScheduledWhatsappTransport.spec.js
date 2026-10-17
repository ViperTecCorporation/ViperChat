import { mount } from '@vue/test-utils';
import ScheduledWhatsappTransport from './ScheduledWhatsappTransport.vue';

describe('scheduled provider selection', () => {
  it('shows no selector or explanation for an unlinked inbox', () => {
    const wrapper = mount(ScheduledWhatsappTransport);
    expect(wrapper.find('select').exists()).toBe(false);
    expect(wrapper.text()).toBe('');
  });

  it('allows Meta scheduling even when its current reply window is closed', async () => {
    const wrapper = mount(ScheduledWhatsappTransport, {
      props: {
        modelValue: 'unoapi',
        legacy: true,
        options: {
          transports: [
            { provider: 'unoapi', can_reply: true },
            { provider: 'whatsapp_cloud', can_reply: false },
          ],
        },
      },
    });
    const meta = wrapper.get('option[value="whatsapp_cloud"]');
    expect(meta.element.disabled).toBe(false);
    await wrapper.get('select').setValue('whatsapp_cloud');
    expect(wrapper.emitted('update:modelValue')).toEqual([['whatsapp_cloud']]);
    expect(wrapper.text()).toContain('Existing schedule');
    expect(wrapper.text()).toContain('at sending time');
    expect(wrapper.get('select').classes()).toContain('min-w-0');
    expect(wrapper.get('select').classes()).toContain('w-full');
  });
});
