import { mount } from '@vue/test-utils';
import { defineComponent, h, ref } from 'vue';
import VoipCall from '../VoipCall.vue';
import { provideMessageContext } from '../../provider';

vi.mock('dashboard/composables/store', () => ({ useMapGetter: () => ref([]) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

describe('VoIP conversation card', () => {
  it('keeps analysis collapsed, escapes provider text and updates it alongside one audio player', async () => {
    const attributes = ref({
      data: { state: 'completed', direction: 'inbound', service_name: 'PBX' },
      voipCallAnalysis: {
        summary: '<img src=x onerror=alert(1)>',
        transcript: 'Hello\nWorld',
      },
    });
    const wrapper = mount(
      defineComponent({
        setup() {
          provideMessageContext({
            contentAttributes: attributes,
            attachments: ref([{ fileType: 'audio', dataUrl: '/audio' }]),
          });
          return () => h(VoipCall);
        },
      }),
      {
        global: {
          stubs: {
            BaseBubble: { template: '<div><slot /></div>' },
            AudioChip: true,
            Icon: true,
          },
        },
      }
    );
    expect(wrapper.findAll('details')).toHaveLength(2);
    expect(wrapper.find('div').classes()).toContain('!bg-n-brand/10');
    expect(wrapper.findAll('details').every(row => !row.element.open)).toBe(
      true
    );
    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.text()).toContain('<img src=x onerror=alert(1)>');
    expect(wrapper.findAllComponents({ name: 'AudioChip' })).toHaveLength(1);
    expect(
      wrapper.findComponent({ name: 'AudioChip' }).props('showTranscribedText')
    ).toBe(false);
    attributes.value.voipCallAnalysis.summary = 'Updated summary';
    await wrapper.vm.$nextTick();
    expect(wrapper.text()).toContain('Updated summary');
    wrapper.unmount();
  });

  it('updates all canonical call states without exposing legacy Voice answer/callback actions', async () => {
    const attributes = ref({
      data: { state: 'ringing', direction: 'inbound', service_name: 'PBX' },
    });
    const attachments = ref([]);
    const wrapper = mount(
      defineComponent({
        setup() {
          provideMessageContext({ contentAttributes: attributes, attachments });
          return () => h(VoipCall);
        },
      }),
      {
        global: {
          stubs: {
            BaseBubble: { template: '<div><slot /></div>' },
            AudioChip: true,
            Icon: true,
          },
        },
      }
    );
    await [
      'routing',
      'ringing',
      'active',
      'completed',
      'missed',
      'failed',
      'cancelled',
    ].reduce(
      (chain, state) =>
        chain.then(async () => {
          attributes.value = {
            data: {
              state,
              direction: 'inbound',
              service_name: 'PBX',
              duration_seconds: 10,
            },
          };
          await wrapper.vm.$nextTick();
          expect(wrapper.text()).toContain(`AGENT_VOIP.CALL_EVENT.${state}`);
          expect(wrapper.findAll('button')).toHaveLength(0);
        }),
      Promise.resolve()
    );
    attachments.value = [
      { fileType: 'audio', dataUrl: '/authenticated-audio' },
    ];
    await wrapper.vm.$nextTick();
    expect(wrapper.findComponent({ name: 'AudioChip' }).exists()).toBe(true);
    wrapper.unmount();
  });
});
