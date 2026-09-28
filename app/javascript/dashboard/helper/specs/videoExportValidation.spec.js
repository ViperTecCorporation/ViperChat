import { Blob } from 'node:buffer';
import {
  hasExplicitSquarePixels,
  isAvc420,
  avcFullRange,
  avcColorRange,
  videoExportIssues,
} from '../videoExportValidation';
import { canKeepVideo } from '../mediaProfiles';

const box = (type, data = new Uint8Array()) => {
  const bytes = new Uint8Array(8 + data.length);
  new DataView(bytes.buffer).setUint32(0, bytes.length);
  bytes.set(
    Array.from(type, c => c.charCodeAt(0)),
    4
  );
  bytes.set(data, 8);
  return bytes;
};
const sample = sar =>
  box(
    'moov',
    box(
      'trak',
      box(
        'mdia',
        box(
          'minf',
          box(
            'stbl',
            box(
              'stsd',
              new Uint8Array([
                ...new Uint8Array(8),
                ...box('avc1', new Uint8Array([...new Uint8Array(78), ...sar])),
              ])
            )
          )
        )
      )
    )
  );
describe('export acceptance', () => {
  it('reports measured color, FPS and bitrate failures, including unknown range', () => {
    const metadata = {
      mp4: true,
      codec: 'avc',
      duration: 10,
      frameRate: 59.94,
      bitrate: 1500000,
      width: 394,
      height: 854,
      square: true,
      rotation: 0,
      avc420: true,
      fullRange: true,
      hasAudio: false,
    };
    expect(videoExportIssues(metadata, { quality: 'sd' }, 1000)).toEqual([
      { field: 'FPS', actual: 59.94, expected: '<= 30 FPS' },
      { field: 'BITRATE', actual: 1500000, expected: '<= 1200000 bps' },
      { field: 'FULL_RANGE', actual: true, expected: false },
    ]);
    expect(
      videoExportIssues(
        { ...metadata, frameRate: 30, bitrate: 1000000, fullRange: undefined },
        { quality: 'sd' },
        1000
      )
    ).toEqual([{ field: 'FULL_RANGE', actual: null, expected: false }]);
    expect(
      videoExportIssues(
        { ...metadata, frameRate: 30, bitrate: 1000000, fullRange: false },
        { quality: 'sd' },
        1000
      )
    ).toEqual([]);
  });
  it('reads the coded range flag and fails closed on truncated SPS', () => {
    const config = fullRange => {
      // Baseline SPS: ue fields=0; progressive, no crop, VUI video signal type.
      const bits =
        '1111' +
        '10' +
        '11' +
        '11' +
        '0' +
        '1' +
        '00' +
        '1' +
        '101' +
        (fullRange ? '1' : '0') +
        '0' +
        '10000000';
      const payload = [];
      for (let i = 0; i < bits.length; i += 8)
        payload.push(parseInt(bits.slice(i, i + 8).padEnd(8, '0'), 2));
      const sps = [103, 66, 0, 40, ...payload];
      return {
        description: new Uint8Array([
          1,
          66,
          0,
          40,
          255,
          225,
          0,
          sps.length,
          ...sps,
        ]),
      };
    };
    expect(avcFullRange(config(false))).toBe(false);
    expect(avcFullRange(config(true))).toBe(true);
    expect(
      avcColorRange({ ...config(false), colorSpace: { fullRange: true } })
        .fullRange
    ).toBe(true);
    expect(
      avcColorRange({ ...config(true), colorSpace: { fullRange: false } })
        .fullRange
    ).toBe(true);
    expect(
      avcColorRange({ ...config(false), colorSpace: { fullRange: false } })
        .fullRange
    ).toBe(false);
    expect(avcColorRange(config(false)).fullRange).toBe(false);
    expect(avcFullRange({ description: new Uint8Array() })).toBeUndefined();
  });
  it.each(['hd', 'sd'])(
    'rejects %s MP4 full range even when the SPS has no VUI',
    quality => {
      const range = avcColorRange({
        // Baseline SPS without VUI: bitstream alone defaults to limited.
        description: new Uint8Array([
          1, 66, 0, 40, 255, 225, 0, 6, 103, 66, 0, 40, 251, 192,
        ]),
        colorSpace: { fullRange: true },
      });
      expect(range).toEqual({
        spsFullRange: false,
        declaredFullRange: true,
        fullRange: true,
      });
      const issues = videoExportIssues(
        {
          mp4: true,
          codec: 'avc',
          duration: 10,
          frameRate: 30,
          bitrate: quality === 'hd' ? 1904069 : 918493,
          width: quality === 'hd' ? 590 : 394,
          height: quality === 'hd' ? 1280 : 854,
          square: true,
          rotation: 0,
          avc420: true,
          hasAudio: false,
          ...range,
        },
        { quality },
        1000
      );
      expect(issues).toEqual([
        { field: 'FULL_RANGE', actual: true, expected: false },
      ]);
    }
  );
  it('does not allow limited container metadata to rescue an unreadable SPS', () => {
    expect(
      avcColorRange({
        description: new Uint8Array(),
        colorSpace: { fullRange: false },
      }).fullRange
    ).toBeUndefined();
    expect(
      avcColorRange({
        description: new Uint8Array(),
        colorSpace: { fullRange: true },
      }).fullRange
    ).toBe(true);
  });
  it('requires explicit 1:1 rather than inferring square pixels', async () => {
    expect(
      await hasExplicitSquarePixels(
        new Blob([
          sample(box('pasp', new Uint8Array([0, 0, 0, 1, 0, 0, 0, 1]))),
        ])
      )
    ).toBe(true);
    expect(
      await hasExplicitSquarePixels(new Blob([sample(new Uint8Array())]))
    ).toBe(false);
    expect(
      await hasExplicitSquarePixels(
        new Blob([
          sample(box('pasp', new Uint8Array([0, 0, 0, 4, 0, 0, 0, 3]))),
        ])
      )
    ).toBe(false);
  });
  it('rejects bitrate overshoot, accepts SD AAC 96k plus tolerance', () => {
    const metadata = {
      mp4: true,
      codec: 'avc',
      width: 640,
      height: 360,
      duration: 10,
      frameRate: 30,
      bitrate: 2954222,
      hasAudio: true,
      audioCodec: 'aac',
      audioBitrate: 100800,
      audioSampleRate: 48000,
      audioChannels: 2,
    };
    expect(canKeepVideo({ size: 1 }, metadata, { quality: 'hd' })).toBe(false);
    expect(
      canKeepVideo(
        { size: 1 },
        { ...metadata, bitrate: 2500001 },
        { quality: 'hd' }
      )
    ).toBe(false);
    expect(
      canKeepVideo(
        { size: 1 },
        { ...metadata, bitrate: 1200000 },
        { quality: 'sd' }
      )
    ).toBe(true);
    expect(
      canKeepVideo(
        { size: 1 },
        { ...metadata, bitrate: 1200001 },
        { quality: 'sd' }
      )
    ).toBe(false);
  });
  it('reads SPS chroma and bit depth rather than assuming any AVC is yuv420p', () => {
    // High profile: seq_id=0, chroma=1, bit_depth_luma/chroma_minus8=0.
    const avcc = bits => ({
      description: new Uint8Array([
        1,
        100,
        0,
        31,
        255,
        225,
        0,
        5,
        103,
        100,
        0,
        31,
        bits,
      ]),
    });
    expect(isAvc420(avcc(0b10101100))).toBe(true);
    expect(isAvc420(avcc(0b10100110))).toBe(false);
    expect(isAvc420({ description: new Uint8Array() })).toBe(false);
  });
});
