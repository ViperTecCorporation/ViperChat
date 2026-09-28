/* eslint-disable max-classes-per-file, class-methods-use-this, lines-between-class-members -- Lightweight codec test doubles. */
/* eslint-disable no-restricted-globals -- Exercise the dedicated worker entrypoint. */
import { Conversion } from 'mediabunny';
import { inspectVideoExport } from '../videoExportValidation';
import { limitedRangeProcessor } from '../videoColorRange';
import '../mediaPreparation.worker';

const timing = vi.hoisted(() => ({ average: 30, maximum: 30 }));

vi.mock('../videoExportValidation', () => ({ inspectVideoExport: vi.fn() }));
vi.mock('../videoColorRange', () => ({
  limitedRangeProcessor: vi.fn(() => vi.fn()),
}));
vi.mock('mediabunny', () => ({
  Input: class {
    async getPrimaryVideoTrack() {
      return {
        displayWidth: 1920,
        displayHeight: 1080,
        getCodec: async () => 'avc',
        computePacketStats: async () => ({
          averagePacketRate: timing.average,
          averageBitrate: 4000000,
        }),
        computeFrameRateMetrics: async () => ({
          bestGuessFrameRate: timing.maximum,
          maxFrameRate: timing.maximum,
        }),
      };
    }
    async getPrimaryAudioTrack() {
      return null;
    }
    async computeDuration() {
      return 6;
    }
    async getFormat() {
      return 'mp4';
    }
    dispose() {}
  },
  BlobSource: class {},
  ALL_FORMATS: [],
  MP4: 'mp4',
  Output: class {
    constructor(options) {
      this.target = options.target;
    }
  },
  BufferTarget: class {
    buffer = new ArrayBuffer(32);
  },
  Mp4OutputFormat: class {},
  Quality: class {
    constructor(options) {
      Object.assign(this, options);
    }
  },
  Conversion: { init: vi.fn() },
  canEncodeAudio: vi.fn(),
}));
describe('browser export acceptance gate', () => {
  let post;
  it('returns measured rejection details without returning a video', async () => {
    const issues = [{ field: 'FULL_RANGE', actual: true, expected: false }];
    inspectVideoExport.mockResolvedValue({
      valid: false,
      bitrate: 800000,
      issues,
    });
    await self.onmessage({
      data: { file: new File(['v'], 'v.mp4'), options: { quality: 'sd' } },
    });
    expect(post).toHaveBeenCalledWith({
      error: 'VIDEO_EXPORT_NONCONFORMING',
      issues,
    });
    expect(post.mock.calls.some(([result]) => result.buffer)).toBe(false);
  });
  beforeEach(() => {
    vi.clearAllMocks();
    timing.average = 30;
    timing.maximum = 30;
    post = vi.spyOn(self, 'postMessage').mockImplementation(() => {});
    Conversion.init.mockResolvedValue({
      isValid: true,
      discardedTracks: [],
      execute: async () => {},
    });
  });
  afterEach(() => post.mockRestore());
  it.each(['hd', 'sd'])(
    'caps 59.94 FPS to 30 for %s even with a low average',
    async quality => {
      timing.average = 24;
      timing.maximum = 60000 / 1001;
      inspectVideoExport.mockResolvedValue({ valid: true });
      await self.onmessage({
        data: { file: new File(['v'], 'v.mp4'), options: { quality } },
      });
      expect(Conversion.init.mock.calls[0][0].video.frameRate).toBe(30);
      expect(limitedRangeProcessor).toHaveBeenCalledWith(
        quality === 'sd' ? 852 : 1280,
        quality === 'sd' ? 480 : 720
      );
      expect(Conversion.init.mock.calls[0][0].video.process).toBeTypeOf(
        'function'
      );
    }
  );
  it.each([24, 25, 30000 / 1001])(
    'preserves %s FPS instead of increasing it to 30',
    async fps => {
      timing.average = fps;
      timing.maximum = fps;
      inspectVideoExport.mockResolvedValue({ valid: true });
      await self.onmessage({
        data: { file: new File(['v'], 'v.mp4'), options: { quality: 'hd' } },
      });
      expect(Conversion.init.mock.calls[0][0].video.frameRate).toBe(fps);
    }
  );
  it('uses CBR and only returns a file after validation succeeds', async () => {
    inspectVideoExport.mockResolvedValue({ valid: true });
    await self.onmessage({
      data: { file: new File(['v'], 'v.mp4'), options: { quality: 'hd' } },
    });
    expect(Conversion.init.mock.calls[0][0].video.quality).toMatchObject({
      bitrateMode: 'constant',
      bitrate: 2000000,
    });
    expect(inspectVideoExport).toHaveBeenCalledOnce();
    expect(post.mock.calls.some(([result]) => result.buffer)).toBe(true);
  });
  it('retries bitrate overshoot once and blocks a still invalid export', async () => {
    inspectVideoExport.mockResolvedValue({ valid: false, bitrate: 1463453 });
    await self.onmessage({
      data: { file: new File(['v'], 'v.mp4'), options: { quality: 'sd' } },
    });
    expect(Conversion.init).toHaveBeenCalledTimes(2);
    expect(Conversion.init.mock.calls[1][0].video.quality.bitrate).toBeLessThan(
      960000
    );
    expect(post).toHaveBeenCalledWith({ notice: 'VIDEO_BITRATE_RETRY' });
    expect(post).toHaveBeenCalledWith({ error: 'VIDEO_EXPORT_NONCONFORMING' });
    expect(post.mock.calls.some(([result]) => result.buffer)).toBe(false);
  });
  it('does not retry a format failure as though it were a bitrate failure', async () => {
    inspectVideoExport.mockResolvedValue({
      valid: false,
      bitrate: 800000,
      square: false,
    });
    await self.onmessage({
      data: { file: new File(['v'], 'v.mp4'), options: { quality: 'sd' } },
    });
    expect(Conversion.init).toHaveBeenCalledOnce();
    expect(post).toHaveBeenCalledWith({ error: 'VIDEO_EXPORT_NONCONFORMING' });
  });
});
