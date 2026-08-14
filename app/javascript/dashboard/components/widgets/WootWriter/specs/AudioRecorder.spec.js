import { flushPromises, mount } from '@vue/test-utils';
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
