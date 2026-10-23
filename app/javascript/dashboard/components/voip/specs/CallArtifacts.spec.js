import { mount, flushPromises } from '@vue/test-utils';
import CallArtifacts from '../CallArtifacts.vue';
import AudioChip from 'next/message/chips/Audio.vue';
import { defineComponent, h, ref } from 'vue';
import { provideMessageContext } from 'next/message/provider';

const recording = vi.hoisted(() => vi.fn());
vi.mock('dashboard/api/voip', () => ({
  VoipAPI: vi.fn(function api(accountId) {
    return { accountId, recording };
  }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

describe('Call artifacts', () => {
  let wrapper;
  const props = {
    accountId: 1,
    callId: 42,
    artifacts: {
      recording: { status: 'available', record_id: 'record-1' },
      recording_available: true,
      recording_url: 'https://untrusted.invalid/credential',
      ai: {
        status: 'completed',
        transcript: '<script>bad()</script>',
        summary: 'Resumo da chamada',
      },
      publication_state: 'complete',
      conversation_id: 12,
      message_id: 34,
    },
  };
  const mountComponent = attributes =>
    mount(CallArtifacts, {
      props: { ...props, ...attributes },
      global: {
        stubs: {
          RouterLink: { props: ['to'], template: '<a :href="to"><slot /></a>' },
        },
      },
    });
  beforeEach(() => {
    recording.mockReset();
    Object.defineProperty(URL, 'createObjectURL', {
      configurable: true,
      value: vi.fn(() => 'blob:authorized-recording'),
    });
    Object.defineProperty(URL, 'revokeObjectURL', {
      configurable: true,
      value: vi.fn(),
    });
  });
  afterEach(() => {
    wrapper?.unmount();
    vi.restoreAllMocks();
    vi.useRealTimers();
  });
  it('keeps the shared bubble player source valid when retrying a local blob', async () => {
    vi.useFakeTimers();
    wrapper = mount(AudioChip, {
      props: {
        orientation: 'left',
        compact: true,
        attachment: {
          dataUrl: 'blob:local-audio',
          fileType: 'audio',
          extension: 'wav',
        },
      },
    });
    vi.spyOn(wrapper.find('audio').element, 'load').mockImplementation(
      () => {}
    );
    await wrapper.find('audio').trigger('error');
    await vi.advanceTimersByTimeAsync(501);
    expect(wrapper.find('source').attributes('src')).toBe('blob:local-audio');
    await wrapper.setProps({
      attachment: {
        dataUrl: 'blob:new-recording',
        fileType: 'audio',
        extension: 'wav',
      },
    });
    expect(wrapper.find('source').attributes('src')).toBe('blob:new-recording');
  });
  it('preserves the bubble player message orientation when no override is provided', () => {
    wrapper = mount(
      defineComponent({
        setup() {
          provideMessageContext({ orientation: ref('right') });
          return () =>
            h(AudioChip, {
              attachment: {
                dataUrl: 'https://example.invalid/audio.wav',
                fileType: 'audio',
              },
            });
        },
      }),
      {
        global: {
          mocks: { $store: { getters: { getSelectedChatAttachments: [] } } },
        },
      }
    );
    expect(wrapper.find('.bg-n-solid-blue').exists()).toBe(true);
    expect(wrapper.findComponent(AudioChip).props('compact')).toBe(false);
  });
  it('escapes AI output and links only to the existing private note', () => {
    wrapper = mountComponent();
    expect(wrapper.text()).toContain('<script>bad()</script>');
    expect(wrapper.find('script').exists()).toBe(false);
    expect(wrapper.find('a').attributes('href')).toBe(
      '/app/accounts/1/conversations/12?messageId=34'
    );
    expect(wrapper.html()).not.toContain('untrusted.invalid');
    expect(recording).not.toHaveBeenCalled();
  });
  it('loads audio through the authorized call API only on demand and releases it when changing calls', async () => {
    recording.mockResolvedValue({
      data: new Blob(['audio'], { type: 'audio/wav' }),
    });
    wrapper = mountComponent();
    await wrapper.find('button').trigger('click');
    await flushPromises();
    expect(recording).toHaveBeenCalledWith(42);
    expect(wrapper.findComponent(AudioChip).props('compact')).toBe(true);
    expect(wrapper.findComponent(AudioChip).props('orientation')).toBe('left');
    expect(wrapper.find('audio source').attributes('src')).toBe(
      'blob:authorized-recording'
    );
    expect(wrapper.find('audio').attributes('autoplay')).toBeUndefined();
    expect(wrapper.findComponent(AudioChip).props('attachment').dataUrl).toBe(
      'blob:authorized-recording'
    );
    await wrapper.setProps({ callId: 43 });
    expect(URL.revokeObjectURL).toHaveBeenCalledWith(
      'blob:authorized-recording'
    );
    expect(wrapper.find('audio').exists()).toBe(false);
  });
  it('keeps a failed download visible and allows retry', async () => {
    recording
      .mockRejectedValueOnce(new Error('unauthorized'))
      .mockResolvedValueOnce({ data: new Blob(['audio']) });
    wrapper = mountComponent();
    await wrapper.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    await wrapper.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(wrapper.find('audio').exists()).toBe(true);
  });
  it('does not attach an old response to a new account or call', async () => {
    let resolve;
    recording.mockReturnValue(
      new Promise(done => {
        resolve = done;
      })
    );
    wrapper = mountComponent();
    await wrapper.find('button').trigger('click');
    await wrapper.setProps({ accountId: 2, callId: 9 });
    resolve({ data: new Blob(['old-account']) });
    await flushPromises();
    expect(URL.createObjectURL).not.toHaveBeenCalled();
    expect(wrapper.find('audio').exists()).toBe(false);
  });
  it('shows processing and safe pending publication without inventing a conversation', () => {
    wrapper = mountComponent({
      artifacts: {
        recording: { status: 'processing' },
        recording_available: false,
        ai: { status: 'queued' },
        publication_state: 'ambiguous',
      },
    });
    expect(wrapper.text()).toContain('STATUS.processing');
    expect(wrapper.text()).toContain('STATUS.queued');
    expect(wrapper.text()).toContain('PUBLICATION.ambiguous');
    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.find('button').exists()).toBe(false);
  });
  it('hides artifact controls for old calls without artifacts', () => {
    wrapper = mountComponent({ artifacts: null });
    expect(wrapper.find('section').exists()).toBe(false);
  });
});
