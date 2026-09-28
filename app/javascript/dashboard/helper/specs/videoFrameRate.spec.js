import { inspectVideoFrameRate } from '../videoFrameRate';
import { videoProfile } from '../mediaProfiles';

describe('video timing and portrait limits', () => {
  it('detects 59.94 FPS behind a 24 FPS average and scans the whole stream', async () => {
    const track = {
      computeFrameRateMetrics: vi.fn().mockResolvedValue({
        bestGuessFrameRate: 60000 / 1001,
        maxFrameRate: 60000 / 1001,
      }),
    };
    expect(
      await inspectVideoFrameRate(track, { averagePacketRate: 24 })
    ).toBeCloseTo(59.94, 2);
    expect(track.computeFrameRateMetrics).toHaveBeenCalledWith({
      targetPacketCount: Infinity,
    });
  });
  it('normalizes only timestamp quantization, not genuinely higher FPS', async () => {
    const track = {
      computeFrameRateMetrics: vi
        .fn()
        .mockResolvedValue({ bestGuessFrameRate: 30, maxFrameRate: 30.0003 }),
    };
    expect(await inspectVideoFrameRate(track, { averagePacketRate: 30 })).toBe(
      30
    );
    track.computeFrameRateMetrics.mockResolvedValue({
      bestGuessFrameRate: 30.01,
      maxFrameRate: 30.01,
    });
    expect(await inspectVideoFrameRate(track, { averagePacketRate: 30 })).toBe(
      30.01
    );
  });
  it('keeps 480x1014 in HD and reduces it proportionally for SD', () => {
    expect(videoProfile(480, 1014, 10, 'hd')).toMatchObject({
      width: 480,
      height: 1014,
    });
    expect(videoProfile(480, 1014, 10, 'sd')).toMatchObject({
      width: 404,
      height: 854,
    });
  });
});
