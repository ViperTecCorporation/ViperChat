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
  it.each([
    { mode: 'NOTE' },
    { isEditorDisabled: true },
    { isReplyRestricted: true },
    { inbox: { channel_type: 'Channel::Email' } },
  ])('hides location in unsupported contexts %j', props => {
    expect(mountComponent(props).vm.canShareLocation).toBe(false);
  });
  it('allows selecting any document extension for WhatsApp', () => {
    const wrapper = mountComponent({});
    expect(wrapper.vm.allowedFileTypes).toBe('*');
  });

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
      .slice(0, 6)
      .map(item => item.text().trim());

    expect(labels).toEqual([
      'CONVERSATION.LOCATION_PICKER.TITLE',
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
  it('offers view once after recording and emits the selected value', async () => {
    const wrapper = mountComponent({
      isRecordingAudio: true,
      recordingAudioState: 'stopped',
      hasRecordedAudio: true,
      allowAudioViewOnce: true,
    });
    await wrapper
      .get('[aria-label="CONVERSATION.VIEW_ONCE_ENABLE"]')
      .trigger('click');
    expect(wrapper.emitted('update:audioViewOnce')).toEqual([[true]]);
    await wrapper.setProps({ hasRecordedAudio: false });
    expect(wrapper.find('[aria-pressed]').exists()).toBe(false);
    wrapper.unmount();
  });
});
