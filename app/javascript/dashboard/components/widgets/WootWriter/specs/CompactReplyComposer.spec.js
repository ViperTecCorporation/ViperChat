import { mount } from '@vue/test-utils';
import CompactReplyComposer from '../CompactReplyComposer.vue';

vi.mock('dashboard/composables/useCaptain', () => ({
  useCaptain: () => ({ captainTasksEnabled: { value: true } }),
}));

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    setSignatureFlagForInbox: vi.fn(),
    fetchSignatureFlagFromUISettings: vi.fn(() => false),
  }),
}));

vi.mock('dashboard/composables', () => ({
  useTrack: vi.fn(),
}));

const ButtonStub = {
  props: {
    icon: { type: String, default: '' },
    disabled: { type: Boolean, default: false },
  },
  emits: ['click'],
  template: `<button
    :data-icon="icon"
    :disabled="disabled"
    @click="$emit('click')"
  />`,
};

const defaultProps = {
  conversationId: 42,
  inbox: {
    channel_type: 'Channel::Whatsapp',
    provider: 'unoapi',
    medium: 'whatsapp',
  },
  showFileUpload: true,
  showAudioRecorder: true,
  showPixButton: true,
  hasContent: false,
  isSendDisabled: true,
};

const mountComponent = props =>
  mount(CompactReplyComposer, {
    props: { ...defaultProps, ...props },
    slots: { default: '<div data-testid="editor" />' },
    global: {
      mocks: {
        $t: key => key,
        $store: {
          getters: {
            getCurrentAccountId: 1,
            'accounts/isFeatureEnabledonAccount': () => true,
          },
        },
      },
      stubs: {
        NextButton: ButtonStub,
        CopilotMenuBar: true,
        FileUpload: { template: '<div class="file-upload"><slot /></div>' },
        VideoCallButton: true,
      },
    },
  });

describe('CompactReplyComposer', () => {
  it('shows plus, attachment, AI and microphone while empty', () => {
    const wrapper = mountComponent();
    const icons = wrapper
      .findAll('button[data-icon]')
      .map(button => button.attributes('data-icon'));

    expect(icons).toEqual([
      'i-lucide-plus',
      'i-ph-paperclip',
      'i-ph-sparkle-fill',
      'i-ph-microphone',
    ]);
  });

  it('replaces the microphone with send when content exists', () => {
    const wrapper = mountComponent({ hasContent: true, isSendDisabled: false });

    expect(wrapper.find('[data-icon="i-ph-microphone"]').exists()).toBe(false);
    expect(wrapper.find('[data-icon="i-lucide-send"]').exists()).toBe(true);
  });

  it('orders the primary plus-menu actions and keeps attachment outside', async () => {
    const wrapper = mountComponent({ isSendDisabled: false });

    await wrapper.find('[data-icon="i-lucide-plus"]').trigger('click');
    const labels = wrapper
      .findAll('.compact-composer__menu-item')
      .slice(0, 5)
      .map(item => item.text().trim());

    expect(labels).toEqual([
      'CONVERSATION.REPLYBOX.COMPACT.EMOJI',
      'CONVERSATION.REPLYBOX.COMPACT.CONTACT',
      'CONVERSATION.REPLYBOX.COMPACT.PIX',
      'CONVERSATION.REPLYBOX.COMPACT.STICKER',
      'CONVERSATION.REPLYBOX.COMPACT.SCHEDULE',
    ]);
    expect(wrapper.find('.file-upload').exists()).toBe(true);
  });

  it('emits the private-note mode from the plus menu', async () => {
    const wrapper = mountComponent();

    await wrapper.find('[data-icon="i-lucide-plus"]').trigger('click');
    const privateNote = wrapper
      .findAll('.compact-composer__menu-item')
      .find(item =>
        item.text().includes('CONVERSATION.REPLYBOX.COMPACT.PRIVATE_NOTE')
      );
    await privateNote.trigger('click');

    expect(wrapper.emitted('setReplyMode')).toEqual([['NOTE']]);
  });

  it('shows the recorded-audio review actions without the normal toolbar', () => {
    const wrapper = mountComponent({
      isRecordingAudio: true,
      recordingAudioState: 'stopped',
      recordingAudioDurationText: '00:03',
      hasRecordedAudio: true,
      isSendDisabled: false,
    });
    const icons = wrapper
      .findAll('button[data-icon]')
      .map(button => button.attributes('data-icon'));

    expect(icons).toEqual([
      'i-ph-trash',
      'i-ph-play-fill',
      'i-ph-microphone',
      'i-lucide-send',
    ]);
    expect(wrapper.text()).toContain('00:03');
  });
});
