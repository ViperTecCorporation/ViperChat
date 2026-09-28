import {
  videoProfile,
  canKeepVideo,
  isEditableMedia,
  VIDEO_LIMIT,
} from '../mediaProfiles';

describe('local media profiles', () => {
  it.each([
    [1920, 1080, 1280, 720],
    [1080, 1920, 720, 1280],
    [640, 360, 640, 360],
    [1000, 1000, 720, 720],
  ])('preserves ratio without upscaling', (w, h, outW, outH) => {
    expect(videoProfile(w, h, 10)).toMatchObject({
      width: outW,
      height: outH,
      bitrate: 2500000,
    });
  });
  it('keeps the profile bitrate for long videos instead of targeting 15 MiB', () => {
    expect(videoProfile(1920, 1080, 900)).toEqual(videoProfile(1920, 1080, 10));
    expect(videoProfile(1920, 1080, 900, 'sd')).toMatchObject({
      width: 852,
      height: 480,
      bitrate: 1200000,
      audioBitrate: 64000,
    });
  });
  it('rejects invalid duration but accepts long clips', () => {
    expect(() => videoProfile(1920, 1080, 0)).toThrow('INVALID_VIDEO');
    expect(videoProfile(1920, 1080, 2000).bitrate).toBe(2500000);
  });
  it('converts 1080p to the selected HD profile', () => {
    expect(
      canKeepVideo(
        { size: 1024 },
        {
          mp4: true,
          codec: 'avc',
          audioCodec: 'aac',
          duration: 10,
          width: 1920,
          height: 1080,
          frameRate: 30,
          bitrate: 1500000,
        },
        { quality: 'hd', end: 10 }
      )
    ).toBe(false);
  });
  it.each([{ mute: true }, { start: 1 }, { end: 2 }, { quality: 'sd' }])(
    'reprocesses explicit edits',
    options => {
      expect(
        canKeepVideo(
          { size: 1024 },
          { mp4: true, codec: 'avc', audioCodec: 'aac', duration: 10 },
          options
        )
      ).toBe(false);
    }
  );
  it('rejects HEVC, oversized MP4 and unsupported editor inputs', () => {
    expect(
      canKeepVideo({ size: VIDEO_LIMIT + 1 }, { mp4: true, codec: 'avc' }, {})
    ).toBe(false);
    expect(canKeepVideo({ size: 1 }, { mp4: true, codec: 'hevc' }, {})).toBe(
      false
    );
    expect(isEditableMedia({ type: 'image/gif' })).toBe(false);
    expect(isEditableMedia({ type: 'image/svg+xml' })).toBe(false);
    expect(isEditableMedia({ type: 'video/mp4' })).toBe(true);
  });
  it('preserves a compatible 185 MiB 720p original', () => {
    expect(
      canKeepVideo(
        { size: 185 * 1024 * 1024 },
        {
          mp4: true,
          codec: 'avc',
          width: 1280,
          height: 720,
          duration: 900,
          frameRate: 24,
          bitrate: 1600000,
          hasAudio: true,
          audioCodec: 'aac',
          audioBitrate: 96000,
          audioChannels: 1,
          audioSampleRate: 48000,
        },
        { quality: 'hd' }
      )
    ).toBe(true);
  });
  it('preserves a compatible SD original and honors a smaller channel cap', () => {
    const metadata = {
      mp4: true,
      codec: 'avc',
      width: 640,
      height: 360,
      duration: 90,
      frameRate: 25,
      bitrate: 800000,
      hasAudio: false,
    };
    expect(
      canKeepVideo({ size: 20 * 1024 * 1024 }, metadata, { quality: 'sd' })
    ).toBe(true);
    expect(
      canKeepVideo({ size: 20 * 1024 * 1024 }, metadata, {
        quality: 'sd',
        maxOutputBytes: 10 * 1024 * 1024,
      })
    ).toBe(false);
  });
});
