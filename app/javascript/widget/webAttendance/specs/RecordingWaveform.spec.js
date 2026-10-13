import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import WaveSurfer from 'wavesurfer.js';
import RecordPlugin from 'wavesurfer.js/dist/plugins/record.js';
import RecordingWaveform from '../RecordingWaveform.vue';
import messages from '../i18n';

vi.mock('wavesurfer.js', () => ({ default: { create: vi.fn() } }));
vi.mock('wavesurfer.js/dist/plugins/record.js', () => ({
  default: { create: vi.fn() },
}));

describe('visitor live waveform', () => {
  it('reuses the recorder stream and releases the visualizer on unmount', () => {
    const onDestroy = vi.fn();
    const destroy = vi.fn();
    const renderMicStream = vi.fn(() => ({ onDestroy }));
    RecordPlugin.create.mockReturnValue({ renderMicStream });
    WaveSurfer.create.mockReturnValue({ destroy });
    const stream = { getTracks: vi.fn() };
    const wrapper = mount(RecordingWaveform, {
      props: { stream },
      global: {
        plugins: [createI18n({ legacy: false, locale: 'pt-BR', messages })],
      },
    });
    expect(RecordPlugin.create).toHaveBeenCalledWith({
      scrollingWaveform: true,
      renderRecordedAudio: false,
    });
    expect(renderMicStream).toHaveBeenCalledWith(stream);
    expect(wrapper.get('[role="img"]').attributes('aria-label')).toBe(
      'Onda do áudio durante a gravação'
    );
    wrapper.unmount();
    expect(onDestroy).toHaveBeenCalledOnce();
    expect(destroy).toHaveBeenCalledOnce();
    expect(stream.getTracks).not.toHaveBeenCalled();
  });

  it('reports visualizer failure without stopping the actual recording', () => {
    const destroy = vi.fn();
    WaveSurfer.create.mockReturnValue({ destroy });
    RecordPlugin.create.mockReturnValue({
      renderMicStream: vi.fn(() => {
        throw new Error('No AudioContext');
      }),
    });
    const stream = { getTracks: vi.fn() };
    const wrapper = mount(RecordingWaveform, {
      props: { stream },
      global: {
        plugins: [createI18n({ legacy: false, locale: 'en', messages })],
      },
    });
    expect(wrapper.vm.$.setupState.failed).toBe(true);
    wrapper.unmount();
    expect(destroy).toHaveBeenCalledOnce();
    expect(stream.getTracks).not.toHaveBeenCalled();
  });
});
