import { Capacitor } from '@capacitor/core';
import { prepareNativeVideo, usesNativeVideo } from '../nativeVideoPreparation';
import { inspectVideoExport } from '../videoExportValidation';

const bridge = vi.hoisted(() => ({
  begin: vi.fn(),
  append: vi.fn(),
  exportVideo: vi.fn(),
  read: vi.fn(),
  cancel: vi.fn(),
  dispose: vi.fn(),
  addListener: vi.fn(),
}));
vi.mock('@capacitor/core', () => ({
  Capacitor: { isNativePlatform: vi.fn(), getPlatform: vi.fn() },
  registerPlugin: () => bridge,
}));
vi.mock('../videoExportValidation', () => ({ inspectVideoExport: vi.fn() }));

describe('native iOS video export', () => {
  it('exposes native stage/code when AVFoundation fails', async () => {
    bridge.exportVideo.mockResolvedValue({
      error: 'VIDEO_UNSUPPORTED',
      diagnostic: 'reader: AVFoundationErrorDomain (-11800)',
    });
    await expect(
      prepareNativeVideo(new File(['src'], 'clip.mov'), {})
    ).rejects.toMatchObject({
      message: 'VIDEO_UNSUPPORTED',
      issues: [
        {
          field: 'NATIVE_EXPORT',
          actual: 'reader: AVFoundationErrorDomain (-11800)',
          expected: 'MP4 / H.264 / AAC',
        },
      ],
    });
    expect(bridge.read).not.toHaveBeenCalled();
    expect(bridge.dispose).toHaveBeenCalled();
  });
  it('cancels a running native export and cleans its files after rejection', async () => {
    const controller = new AbortController();
    bridge.exportVideo.mockImplementation(async () => {
      controller.abort();
      throw new Error('AbortError');
    });
    bridge.cancel.mockResolvedValue({});
    await expect(
      prepareNativeVideo(
        new File(['src'], 'clip.mov'),
        {},
        { signal: controller.signal }
      )
    ).rejects.toMatchObject({ name: 'AbortError' });
    expect(bridge.cancel).toHaveBeenCalledWith({ id: 'test-export' });
    expect(bridge.dispose).toHaveBeenCalledWith({ id: 'test-export' });
  });
  beforeEach(() => {
    vi.resetAllMocks();
    bridge.begin.mockResolvedValue({ id: 'test-export' });
    bridge.addListener.mockResolvedValue({ remove: vi.fn() });
    bridge.exportVideo.mockResolvedValue({ size: 3 });
    bridge.read.mockResolvedValue({ data: btoa('mp4') });
    inspectVideoExport.mockResolvedValue({ valid: true });
  });
  it('only routes native iOS to AVFoundation', () => {
    Capacitor.isNativePlatform.mockReturnValue(true);
    Capacitor.getPlatform.mockReturnValue('ios');
    expect(usesNativeVideo()).toBe(true);
    Capacitor.getPlatform.mockReturnValue('android');
    expect(usesNativeVideo()).toBe(false);
    Capacitor.isNativePlatform.mockReturnValue(false);
    Capacitor.getPlatform.mockReturnValue('ios');
    expect(usesNativeVideo()).toBe(false);
  });
  it('passes trim, mute and SD, validates bytes and removes native files', async () => {
    const options = { quality: 'sd', start: 2, end: 4, mute: true };
    const result = await prepareNativeVideo(
      new File(['source'], 'clip.mov'),
      options
    );
    expect(bridge.append).toHaveBeenCalledWith({
      id: 'test-export',
      data: btoa('source'),
    });
    expect(bridge.exportVideo).toHaveBeenCalledWith({
      id: 'test-export',
      ...options,
    });
    expect(result.name).toBe('clip.mp4');
    expect(result.size).toBe(3);
    expect(inspectVideoExport).toHaveBeenCalledWith(result, options);
    expect(bridge.dispose).toHaveBeenCalledWith({ id: 'test-export' });
  });
  it('keeps detailed diagnostics and cleans up rejected exports', async () => {
    const issues = [{ field: 'FULL_RANGE', actual: true, expected: false }];
    inspectVideoExport.mockResolvedValue({ valid: false, issues });
    await expect(
      prepareNativeVideo(new File(['src'], 'clip.mov'), {})
    ).rejects.toMatchObject({ message: 'VIDEO_EXPORT_NONCONFORMING', issues });
    expect(bridge.dispose).toHaveBeenCalled();
  });
  it('does not start an already canceled export', async () => {
    const controller = new AbortController();
    controller.abort();
    await expect(
      prepareNativeVideo(
        new File(['src'], 'clip.mov'),
        {},
        { signal: controller.signal }
      )
    ).rejects.toMatchObject({ name: 'AbortError' });
    expect(bridge.begin).not.toHaveBeenCalled();
  });
  it('cleans up when the native encoder fails', async () => {
    bridge.exportVideo.mockRejectedValue(new Error('VIDEO_UNSUPPORTED'));
    await expect(
      prepareNativeVideo(new File(['src'], 'clip.mov'), {})
    ).rejects.toThrow('VIDEO_UNSUPPORTED');
    expect(bridge.dispose).toHaveBeenCalled();
  });
  it('rejects oversized output before reading it', async () => {
    bridge.exportVideo.mockResolvedValue({ size: 257 * 1024 * 1024 });
    await expect(
      prepareNativeVideo(new File(['src'], 'clip.mov'), {})
    ).rejects.toThrow('VIDEO_TOO_LARGE');
    expect(bridge.read).not.toHaveBeenCalled();
    expect(bridge.dispose).toHaveBeenCalled();
  });
});
