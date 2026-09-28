import { mount, flushPromises } from '@vue/test-utils';
import MediaEditor from './MediaEditor.vue';
import { prepareImage, prepareVideo } from 'dashboard/helper/mediaPreparation';
import { useAlert } from 'dashboard/composables';
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/helper/mediaPreparation', () => ({
  prepareImage: vi.fn(async file => file),
  prepareVideo: vi.fn(async file => file),
}));

describe('media editor batch', () => {
  const image = () => new File(['img'], 'one.jpg', { type: 'image/jpeg' });
  const mountEditor = (props = {}) =>
    mount(MediaEditor, {
      props: {
        files: [image()],
        caption: 'Initial caption',
        submitFile: vi.fn(async () => ({ ok: true, dispatched: true })),
        ...props,
      },
      global: {
        stubs: {
          Teleport: true,
          MediaImageCanvas: true,
          Icon: true,
          MediaPreviewZoom: { template: '<div><slot /></div>' },
        },
      },
    });
  it('shows measured rejection values and clears them on retry without uploading', async () => {
    prepareVideo.mockRejectedValueOnce(
      Object.assign(new Error('VIDEO_EXPORT_NONCONFORMING'), {
        issues: [
          { field: 'BITRATE', actual: 1463453, expected: '<= 1200000 bps' },
        ],
      })
    );
    const wrapper = mountEditor({
      files: [new File(['v'], 'v.mp4', { type: 'video/mp4' })],
    });
    await wrapper.get('[aria-label="MEDIA_EDITOR.SEND"]').trigger('click');
    await flushPromises();
    const details = wrapper.get('[data-testid="video-export-issues"]');
    expect(details.text()).toContain('1463453');
    expect(details.text()).toContain('<= 1200000 bps');
    expect(wrapper.props('submitFile')).not.toHaveBeenCalled();
    prepareVideo.mockRejectedValueOnce(new Error('VIDEO_UNSUPPORTED'));
    await wrapper.get('[aria-label="MEDIA_EDITOR.SEND"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="video-export-issues"]').exists()).toBe(
      false
    );
    wrapper.unmount();
  });
  it('offers explicit server processing when the exported file fails acceptance', async () => {
    prepareVideo.mockRejectedValueOnce(new Error('VIDEO_EXPORT_NONCONFORMING'));
    const wrapper = mountEditor({
      files: [new File(['v'], 'v.mp4', { type: 'video/mp4' })],
    });
    await wrapper.get('[aria-label="MEDIA_EDITOR.SEND"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('MEDIA_EDITOR.VIDEO_EXPORT_NONCONFORMING');
    expect(wrapper.text()).toContain('MEDIA_EDITOR.SERVER_FALLBACK');
    expect(wrapper.props('submitFile')).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('shows upload bytes and progress inside the modal, then waits for completion', async () => {
    let finish;
    let notify;
    const submitFile = vi.fn((_file, _caption, options) => {
      notify = options.onProgress;
      return new Promise(resolve => {
        finish = resolve;
      });
    });
    const wrapper = mountEditor({ submitFile });
    await wrapper.get('[aria-label="MEDIA_EDITOR.SEND"]').trigger('click');
    await flushPromises();
    notify({
      phase: 'UPLOADING',
      percent: 50,
      loaded: 1048576,
      total: 2097152,
    });
    await flushPromises();
    expect(wrapper.get('[role="status"]').text()).toContain('50%');
    expect(wrapper.get('[role="status"]').text()).toContain('1.0 / 2.0 MiB');
    expect(wrapper.get('progress').attributes('value')).toBe('50');
    notify({ phase: 'COMPLETING', percent: null });
    await flushPromises();
    expect(wrapper.get('progress').attributes('value')).toBeUndefined();
    expect(wrapper.emitted('close')).toBeUndefined();
    finish({ ok: true, dispatched: true });
    await flushPromises();
    expect(wrapper.emitted('close')).toHaveLength(1);
    wrapper.unmount();
  });
  beforeEach(() => {
    vi.clearAllMocks();
    URL.createObjectURL = vi.fn(() => 'blob:test');
    URL.revokeObjectURL = vi.fn();
  });
  it('does not upload on open, gives caption only to first item, keeps individual captions', async () => {
    const wrapper = mountEditor({ files: [image(), image()] });
    expect(wrapper.props('submitFile')).not.toHaveBeenCalled();
    expect(wrapper.get('textarea').element.value).toBe('Initial caption');
    await wrapper
      .get('[aria-label="MEDIA_EDITOR.ATTACHMENT 2"]')
      .trigger('click');
    expect(wrapper.get('textarea').element.value).toBe('');
    await wrapper.get('textarea').setValue('Second caption');
    await wrapper.get('[aria-label="MEDIA_EDITOR.SEND"]').trigger('click');
    await flushPromises();
    expect(wrapper.props('submitFile').mock.calls.map(call => call[1])).toEqual(
      ['Initial caption', 'Second caption']
    );
    expect(wrapper.emitted('close')).toHaveLength(1);
    wrapper.unmount();
  });
  it('does not resubmit a failed dispatched message', async () => {
    const submitFile = vi
      .fn()
      .mockResolvedValueOnce({ ok: false, dispatched: true })
      .mockResolvedValue({ ok: true, dispatched: true });
    const wrapper = mountEditor({ files: [image(), image()], submitFile });
    await wrapper.get('[aria-label="MEDIA_EDITOR.SEND"]').trigger('click');
    await flushPromises();
    expect(submitFile).toHaveBeenCalledTimes(1);
    await wrapper.get('[aria-label="MEDIA_EDITOR.SEND"]').trigger('click');
    await flushPromises();
    expect(submitFile).toHaveBeenCalledTimes(2);
    expect(submitFile.mock.calls[1][1]).toBe('');
    wrapper.unmount();
  });
  it('keeps an upload failure for retry', async () => {
    const submitFile = vi
      .fn()
      .mockResolvedValue({ ok: false, dispatched: false });
    const wrapper = mountEditor({ submitFile });
    await wrapper.get('[aria-label="MEDIA_EDITOR.SEND"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('textarea').element.value).toBe('Initial caption');
    expect(wrapper.emitted('close')).toBeUndefined();
    wrapper.unmount();
  });
  it('does not report an upload exception as an image preparation error', async () => {
    const submitFile = vi
      .fn()
      .mockRejectedValue(new TypeError('Upload failed'));
    const wrapper = mountEditor({ submitFile });
    await wrapper.get('[aria-label="MEDIA_EDITOR.SEND"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('MEDIA_EDITOR.UPLOAD_FAILED');
    expect(wrapper.text()).not.toContain('MEDIA_EDITOR.IMAGE_ERROR');
    expect(wrapper.text()).not.toContain('TypeError');
    expect(wrapper.emitted('close')).toBeUndefined();
    wrapper.unmount();
  });
  it('closes an empty editor after dispatch failure and directs retry to the existing bubble', async () => {
    const submitFile = vi
      .fn()
      .mockResolvedValue({ ok: false, dispatched: true });
    const wrapper = mountEditor({ submitFile });
    await wrapper.get('[aria-label="MEDIA_EDITOR.SEND"]').trigger('click');
    await flushPromises();
    expect(submitFile).toHaveBeenCalledTimes(1);
    expect(wrapper.emitted('close')).toHaveLength(1);
    expect(useAlert).toHaveBeenCalledWith('MEDIA_EDITOR.SEND_FAILED');
    wrapper.unmount();
  });
  it('prepares the entire batch before sending and retains it on conversion failure', async () => {
    prepareVideo.mockRejectedValueOnce(new Error('VIDEO_UNSUPPORTED'));
    const wrapper = mountEditor({
      files: [image(), new File(['video'], 'v.mp4', { type: 'video/mp4' })],
    });
    await wrapper.get('[aria-label="MEDIA_EDITOR.SEND"]').trigger('click');
    await flushPromises();
    expect(prepareImage).toHaveBeenCalled();
    expect(wrapper.props('submitFile')).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('VIDEO_UNSUPPORTED');
    wrapper.unmount();
  });
  it('keeps a video selected if the result exceeds the configured upload limit', async () => {
    prepareVideo.mockRejectedValueOnce(new Error('VIDEO_TOO_LARGE'));
    const wrapper = mountEditor({
      files: [
        new File(['large-video'], '15-minutes.mp4', { type: 'video/mp4' }),
      ],
    });
    await wrapper.get('[aria-label="MEDIA_EDITOR.SEND"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('VIDEO_TOO_LARGE');
    expect(wrapper.find('video').exists()).toBe(true);
    expect(wrapper.props('submitFile')).not.toHaveBeenCalled();
    expect(wrapper.emitted('close')).toBeUndefined();
    wrapper.unmount();
  });
  it('releases object URLs on cancellation without sending', async () => {
    const wrapper = mountEditor();
    await wrapper.get('[aria-label="MEDIA_EDITOR.CLOSE"]').trigger('click');
    expect(wrapper.props('submitFile')).not.toHaveBeenCalled();
    wrapper.unmount();
    expect(URL.revokeObjectURL).toHaveBeenCalled();
  });
  it('rejects input videos over 256 MiB before preparation', () => {
    const file = new File(['video'], 'large.mp4', { type: 'video/mp4' });
    Object.defineProperty(file, 'size', { value: 257 * 1024 * 1024 });
    const wrapper = mountEditor({ files: [file] });
    expect(wrapper.text()).toContain('VIDEO_INPUT_TOO_LARGE');
    expect(prepareVideo).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('passes the inbox output cap to conversion instead of a fixed 15 MiB', async () => {
    const wrapper = mountEditor({
      files: [new File(['video'], 'v.mp4', { type: 'video/mp4' })],
      maxVideoOutputBytes: 80 * 1024 * 1024,
    });
    await wrapper.get('[aria-label="MEDIA_EDITOR.SEND"]').trigger('click');
    await flushPromises();
    expect(prepareVideo.mock.calls[0][1].maxOutputBytes).toBe(80 * 1024 * 1024);
    expect(wrapper.props('submitFile').mock.calls[0][2]).toEqual({
      videoQuality: 'hd',
      onProgress: expect.any(Function),
    });
    wrapper.unmount();
  });
  it('forwards the selected SD quality to submission', async () => {
    const wrapper = mountEditor({
      files: [new File(['video'], 'sd.mp4', { type: 'video/mp4' })],
    });
    await wrapper.get('[aria-label="MEDIA_EDITOR.QUALITY"]').trigger('click');
    await wrapper.get('[aria-label="MEDIA_EDITOR.SEND"]').trigger('click');
    await flushPromises();
    expect(prepareVideo.mock.calls[0][1].quality).toBe('sd');
    expect(wrapper.props('submitFile').mock.calls[0][2]).toEqual({
      videoQuality: 'sd',
      onProgress: expect.any(Function),
    });
    wrapper.unmount();
  });
  it('offers adjustable crop, fonts, thickness and the shared compact send button', async () => {
    const wrapper = mountEditor();
    await wrapper.get('[aria-label="MEDIA_EDITOR.CROP"]').trigger('click');
    expect(wrapper.text()).toContain('MEDIA_EDITOR.APPLY_CROP');
    expect(wrapper.text()).toContain('MEDIA_EDITOR.CANCEL_CROP');
    await wrapper.get('[aria-label="MEDIA_EDITOR.TEXT"]').trigger('click');
    expect(wrapper.get('select').findAll('option')).toHaveLength(10);
    await wrapper.get('[aria-label="MEDIA_EDITOR.DRAW"]').trigger('click');
    await wrapper.get('input[type="range"]').setValue('12');
    expect(
      wrapper.findComponent({ name: 'MediaImageCanvas' }).props('thickness')
    ).toBe(12);
    expect(wrapper.get('[aria-label="MEDIA_EDITOR.SEND"]').classes()).toContain(
      '!rounded-full'
    );
    wrapper.unmount();
  });
  it('keeps editable scenes in undo history instead of flattening them permanently', async () => {
    const wrapper = mountEditor();
    const first = wrapper.props('files')[0];
    const scene = {
      base: first,
      nodes: [{ className: 'Text', attrs: { text: 'Hello' } }],
    };
    wrapper.vm.changedImage(image(), scene);
    await flushPromises();
    expect(wrapper.vm.current.scene).toEqual(scene);
    wrapper.vm.changedImage(image(), { ...scene, nodes: [] });
    await flushPromises();
    await wrapper.get('[aria-label="MEDIA_EDITOR.UNDO"]').trigger('click');
    expect(wrapper.vm.current.scene).toEqual(scene);
    wrapper.unmount();
  });
});
