import { flushPromises, mount } from '@vue/test-utils';
import WaveSurfer from 'wavesurfer.js';
import AudioRecorder from '../AudioRecorder.vue';

const startRecording = vi.fn();
const stopRecording = vi.fn();
const recordOn = vi.fn();
const waveOn = vi.fn();
const destroy = vi.fn();

vi.mock('wavesurfer.js', () => ({
  default: {
    create: vi.fn(() => ({
      plugins: [
        {
          on: recordOn,
          startRecording,
          stopRecording,
        },
      ],
      on: waveOn,
      destroy,
    })),
  },
}));

vi.mock('wavesurfer.js/dist/plugins/record.js', () => ({
  default: { create: vi.fn(() => ({})) },
}));

describe('AudioRecorder', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    document.documentElement.style.removeProperty('--brand-color');
  });

  it('uses the customized primary theme color for the recording waveform', async () => {
    document.documentElement.style.setProperty('--brand-color', '17 34 51');

    mount(AudioRecorder, {
      props: { audioRecordFormat: 'audio/mp3' },
    });
    await flushPromises();

    expect(WaveSurfer.create).toHaveBeenCalledWith(
      expect.objectContaining({
        waveColor: 'rgba(17, 34, 51, 0.55)',
        progressColor: 'rgb(17, 34, 51)',
      })
    );
  });

  it('reports a microphone startup error instead of failing silently', async () => {
    const error = new Error('Permission was not granted');
    startRecording.mockRejectedValueOnce(error);

    const wrapper = mount(AudioRecorder, {
      props: { audioRecordFormat: 'audio/mp3' },
    });
    await flushPromises();

    expect(wrapper.emitted('recordError')).toEqual([[{ error }]]);
  });
});
