import { mount } from '@vue/test-utils';
import ScheduledMessageSequenceEditor from './ScheduledMessageSequenceEditor.vue';

const ButtonStub = {
  inheritAttrs: false,
  template: '<button v-bind="$attrs"><slot /></button>',
};

const mountEditor = attachments =>
  mount(ScheduledMessageSequenceEditor, {
    props: {
      modelValue: [
        {
          content: '',
          attachments,
          voice_message: true,
        },
      ],
      audioRecordFormat: 'mp3',
    },
    global: {
      stubs: {
        Button: ButtonStub,
        FileUpload: { template: '<div><slot /></div>' },
        Icon: true,
        TextArea: true,
        AudioRecorder: true,
        WootMessageEditor: true,
      },
    },
  });

describe('ScheduledMessageSequenceEditor', () => {
  it('shows playback controls for a recorded audio attachment', () => {
    const wrapper = mountEditor([
      {
        signedId: 'signed-audio',
        name: 'voice.mp3',
        voiceMessage: true,
        previewUrl: '/rails/active_storage/blobs/redirect/audio/voice.mp3',
      },
    ]);

    const player = wrapper.get('audio');
    expect(player.attributes('controls')).toBeDefined();
    expect(player.attributes('src')).toBe(
      '/rails/active_storage/blobs/redirect/audio/voice.mp3'
    );
  });

  it('does not show an audio player for regular attachments', () => {
    const wrapper = mountEditor([
      {
        signedId: 'signed-file',
        name: 'document.pdf',
        voiceMessage: false,
        previewUrl: '/rails/active_storage/blobs/redirect/file/document.pdf',
      },
    ]);

    expect(wrapper.find('audio').exists()).toBe(false);
  });
});
