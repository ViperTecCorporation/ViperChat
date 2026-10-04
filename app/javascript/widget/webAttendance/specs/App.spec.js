import { ref, shallowRef } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import App from '../App.vue';
import { useAttendance } from '../useAttendance';
import messages from '../i18n';

vi.mock('../useAttendance', () => ({ useAttendance: vi.fn() }));

describe('visitor audio composer', () => {
  it('shows live waveform and cancel, then playback and a dedicated delete control', async () => {
    const attendance = {
      authenticated: ref(true),
      messages: ref([]),
      name: ref('Support'),
      contactName: ref(''),
      state: ref('active'),
      hasMore: ref(false),
      loadingOlder: ref(false),
      draft: ref(''),
      files: ref([]),
      sending: ref(false),
      error: ref(''),
      recording: ref(true),
      startingRecording: ref(false),
      canRecord: ref(true),
      voiceUrl: ref(''),
      recordingStream: shallowRef({}),
      cancelRecording: vi.fn(),
      removeVoice: vi.fn(),
      stopRecording: vi.fn(),
      startRecording: vi.fn(),
      send: vi.fn(),
      refresh: vi.fn(),
      older: vi.fn(),
      addFiles: vi.fn(),
      removeFile: vi.fn(),
    };
    useAttendance.mockReturnValue(attendance);
    const wrapper = mount(App, {
      global: {
        plugins: [createI18n({ legacy: false, locale: 'pt-BR', messages })],
        stubs: { RecordingWaveform: true },
      },
    });
    expect(wrapper.findComponent({ name: 'RecordingWaveform' }).exists()).toBe(
      true
    );
    expect(
      wrapper.get('button[type="submit"]').attributes('disabled')
    ).toBeDefined();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Cancelar gravação')
      .trigger('click');
    expect(attendance.cancelRecording).toHaveBeenCalledOnce();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Concluir gravação')
      .trigger('click');
    expect(attendance.stopRecording).toHaveBeenCalledOnce();
    attendance.recording.value = false;
    attendance.recordingStream.value = null;
    attendance.files.value = [new File(['voice'], 'voice.webm')];
    attendance.voiceUrl.value = 'blob:voice';
    await wrapper.vm.$nextTick();
    expect(wrapper.get('audio').attributes('src')).toBe('blob:voice');
    expect(wrapper.get('audio').attributes()).not.toHaveProperty('autoplay');
    expect(
      wrapper.get('button[type="submit"]').attributes('disabled')
    ).toBeUndefined();
    expect(wrapper.get('button[type="submit"]').classes()).toContain(
      'bg-n-brand'
    );
    await wrapper.get('textarea').trigger('keydown', { key: 'Enter' });
    expect(attendance.send).toHaveBeenCalledOnce();
    await wrapper
      .get('textarea')
      .trigger('keydown', { key: 'Enter', shiftKey: true });
    await wrapper
      .get('textarea')
      .trigger('keydown', { key: 'Enter', isComposing: true });
    expect(attendance.send).toHaveBeenCalledOnce();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Excluir áudio gravado')
      .trigger('click');
    expect(attendance.removeVoice).toHaveBeenCalledOnce();
    attendance.sending.value = true;
    await wrapper.vm.$nextTick();
    expect(
      wrapper
        .findAll('button')
        .find(button => button.text() === 'Excluir áudio gravado')
        .attributes('disabled')
    ).toBeDefined();
    await wrapper.get('textarea').trigger('keydown', { key: 'Enter' });
    expect(attendance.send).toHaveBeenCalledOnce();
    attendance.sending.value = false;
    attendance.files.value = [];
    attendance.draft.value = '';
    await wrapper.vm.$nextTick();
    expect(wrapper.get('button[type="submit"]').classes()).toContain(
      'bg-n-alpha-2'
    );
    attendance.draft.value = 'Hello';
    await wrapper.vm.$nextTick();
    expect(wrapper.get('button[type="submit"]').classes()).toContain(
      'bg-n-brand'
    );
    wrapper.unmount();
  });
});
