/* eslint-disable no-await-in-loop -- MP4 box offsets are sequential. */
/* eslint-disable no-bitwise, no-continue, no-plusplus -- Parse binary AVC SPS fields. */
import { Input, BlobSource, ALL_FORMATS } from 'mediabunny';
import { canKeepVideo, VIDEO_LIMIT } from './mediaProfiles';
import { hasMp4FastStart } from './mp4FastStart';
import { inspectVideoFrameRate } from './videoFrameRate';

// Container color hints and SPS can disagree on Android. Conservatively require
// limited range in the coded stream instead of relabeling full-range pixels.
export function avcFullRange(config) {
  try {
    const raw = config?.description;
    const bytes = ArrayBuffer.isView(raw)
      ? new Uint8Array(raw.buffer, raw.byteOffset, raw.byteLength)
      : new Uint8Array(raw);
    if (bytes[0] !== 1 || !(bytes[5] & 31)) return undefined;
    const length = (bytes[6] << 8) | bytes[7];
    if (length < 5 || length + 8 > bytes.length) return undefined;
    const sps = [];
    for (let i = 9; i < 8 + length; i += 1) {
      if (bytes[i] === 3 && bytes[i - 1] === 0 && bytes[i - 2] === 0) continue;
      sps.push(bytes[i]);
    }
    let bit = 0;
    const read = (count = 1) => {
      let value = 0;
      for (let i = 0; i < count; i += 1) {
        if (bit >= sps.length * 8) throw new Error('Truncated SPS');
        value = value * 2 + ((sps[Math.floor(bit / 8)] >> (7 - (bit % 8))) & 1);
        bit += 1;
      }
      return value;
    };
    const ue = () => {
      let zeros = 0;
      while (!read()) {
        if (++zeros > 24) throw new Error('Invalid SPS');
      }
      return 2 ** zeros - 1 + read(zeros);
    };
    const se = () => {
      const value = ue();
      return value % 2 ? (value + 1) / 2 : -value / 2;
    };
    const profile = read(8);
    read(16);
    ue();
    if (
      [100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135].includes(
        profile
      )
    ) {
      const chroma = ue();
      if (chroma === 3) read();
      ue();
      ue();
      read();
      if (read()) {
        for (let i = 0; i < (chroma === 3 ? 12 : 8); i += 1) {
          if (read()) {
            let last = 8;
            let next = 8;
            for (let j = 0; j < (i < 6 ? 16 : 64); j += 1) {
              if (next !== 0) next = (last + se() + 256) % 256;
              if (next !== 0) last = next;
            }
          }
        }
      }
    }
    ue();
    const poc = ue();
    if (poc === 0) ue();
    else if (poc === 1) {
      read();
      se();
      se();
      const count = ue();
      if (count > 255) return undefined;
      for (let i = 0; i < count; i += 1) se();
    }
    ue();
    read();
    ue();
    ue();
    if (!read()) read();
    read();
    if (read()) {
      ue();
      ue();
      ue();
      ue();
    }
    if (!read()) return false; // No VUI: video_full_range_flag defaults to 0.
    if (read() && read(8) === 255) {
      read(16);
      read(16);
    }
    if (read()) read();
    if (!read()) return false;
    read(3);
    return !!read();
  } catch {
    return undefined;
  }
}

export function isAvc420(config) {
  try {
    const raw = config?.description;
    const bytes = ArrayBuffer.isView(raw)
      ? new Uint8Array(raw.buffer, raw.byteOffset, raw.byteLength)
      : new Uint8Array(raw);
    if (bytes[0] !== 1 || !(bytes[5] & 31)) return false;
    const length = (bytes[6] << 8) | bytes[7];
    if (length < 5 || length + 8 > bytes.length) return false;
    const sps = [];
    for (let i = 9; i < 8 + length; i += 1) {
      if (bytes[i] === 3 && bytes[i - 1] === 0 && bytes[i - 2] === 0) continue;
      sps.push(bytes[i]);
    }
    if ([66, 77, 88].includes(sps[0])) return true; // Baseline/Main/Extended: 8-bit 4:2:0.
    if (
      ![100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135].includes(
        sps[0]
      )
    )
      return false;
    let bit = 24;
    const read = () => {
      if (bit >= sps.length * 8) throw new Error('Truncated SPS');
      const value = (sps[Math.floor(bit / 8)] >> (7 - (bit % 8))) & 1;
      bit += 1;
      return value;
    };
    const ue = () => {
      let zeros = 0;
      while (!read()) {
        if (++zeros > 30) throw new Error('Invalid SPS');
      }
      let value = 1;
      for (let i = 0; i < zeros; i += 1) value = value * 2 + read();
      return value - 1;
    };
    ue(); // seq_parameter_set_id
    const chroma = ue();
    if (chroma === 3) read();
    return chroma === 1 && ue() === 0 && ue() === 0;
  } catch {
    return false;
  }
}

export function avcColorRange(config) {
  const spsFullRange = avcFullRange(config);
  // Mediabunny exposes MP4 colr/nclx here, falling back to the bitstream when absent.
  // A missing VUI defaults to limited in H.264, but must not override nclx full range.
  // Conversely, limited container metadata must never hide full-range coded video.
  const declaredFullRange = config?.colorSpace?.fullRange;
  const fullRange =
    spsFullRange === true || declaredFullRange === true ? true : spsFullRange;
  return { spsFullRange, declaredFullRange, fullRange };
}

// Inspect the explicit pasp in AVC sample entries, not dimensions inferred by a decoder.
function squareAvcSamples(buffer) {
  const view = new DataView(buffer);
  const values = [];
  function visit(start, end, depth = 0) {
    if (depth > 8) throw new Error('Invalid MP4 nesting');
    for (let pos = start; pos + 8 <= end; ) {
      const size = view.getUint32(pos);
      if (size < 8 || pos + size > end) throw new Error('Invalid MP4 box');
      const type = String.fromCharCode(...new Uint8Array(buffer, pos + 4, 4));
      if (['moov', 'trak', 'mdia', 'minf', 'stbl'].includes(type))
        visit(pos + 8, pos + size, depth + 1);
      if (type === 'stsd') visit(pos + 16, pos + size, depth + 1);
      if (['avc1', 'avc3'].includes(type)) {
        let square = false;
        for (let child = pos + 86; child + 8 <= pos + size; ) {
          const length = view.getUint32(child);
          if (length < 8 || child + length > pos + size)
            throw new Error('Invalid sample entry');
          const name = String.fromCharCode(
            ...new Uint8Array(buffer, child + 4, 4)
          );
          if (name === 'pasp' && length === 16)
            square =
              view.getUint32(child + 8) === 1 &&
              view.getUint32(child + 12) === 1;
          child += length;
        }
        values.push(square);
      }
      pos += size;
    }
  }
  visit(0, buffer.byteLength);
  return values.length > 0 && values.every(Boolean);
}

export async function hasExplicitSquarePixels(file) {
  try {
    for (let offset = 0; offset + 8 <= file.size; ) {
      const header = new DataView(
        await file.slice(offset, offset + 16).arrayBuffer()
      );
      let size = header.getUint32(0);
      const type = String.fromCharCode(...new Uint8Array(header.buffer, 4, 4));
      if (size === 1) size = Number(header.getBigUint64(8));
      if (size === 0) size = file.size - offset;
      if (!Number.isSafeInteger(size) || size < 8 || offset + size > file.size)
        return false;
      if (type === 'moov') {
        if (size > 16 * 1024 * 1024) return false;
        return squareAvcSamples(
          await file.slice(offset, offset + size).arrayBuffer()
        );
      }
      offset += size;
    }
  } catch {
    return false;
  }
  return false;
}

// Only measured media properties: never include tokens, URLs or file contents.
export function videoExportIssues(metadata, options, size) {
  const sd = options.quality === 'sd';
  const issues = [];
  const check = (field, valid, actual, expected) => {
    if (!valid) issues.push({ field, actual: actual ?? null, expected });
  };
  const positive = value => Number.isFinite(value) && value > 0;
  check('FASTSTART', metadata.mp4 === true, metadata.mp4, true);
  check('CODEC', metadata.codec === 'avc', metadata.codec, 'avc / H.264');
  check('DURATION', positive(metadata.duration), metadata.duration, '> 0 s');
  check(
    'FPS',
    positive(metadata.frameRate) && metadata.frameRate <= 30,
    metadata.frameRate,
    '<= 30 FPS'
  );
  const bitrate = sd ? 1200000 : 2500000;
  check(
    'BITRATE',
    positive(metadata.bitrate) && metadata.bitrate <= bitrate,
    metadata.bitrate,
    `<= ${bitrate} bps`
  );
  const long = sd ? 854 : 1280;
  const short = sd ? 480 : 720;
  check(
    'DIMENSIONS',
    positive(metadata.width) &&
      positive(metadata.height) &&
      Math.max(metadata.width, metadata.height) <= long &&
      Math.min(metadata.width, metadata.height) <= short &&
      metadata.width % 2 === 0 &&
      metadata.height % 2 === 0,
    `${metadata.width} x ${metadata.height}`,
    `<= ${long} x ${short}`
  );
  check('SAR', metadata.square === true, metadata.square, true);
  check('ROTATION', metadata.rotation === 0, metadata.rotation, '0');
  check('CHROMA', metadata.avc420 === true, metadata.avc420, true);
  check('FULL_RANGE', metadata.fullRange === false, metadata.fullRange, false);
  const limit = Math.min(VIDEO_LIMIT, options.maxOutputBytes || VIDEO_LIMIT);
  check('SIZE', size <= limit, size, `<= ${limit} bytes`);
  if (metadata.hasAudio) {
    check(
      'AUDIO_CODEC',
      metadata.audioCodec === 'aac' && metadata.audioProfile === 'mp4a.40.2',
      `${metadata.audioCodec} / ${metadata.audioProfile}`,
      'aac / mp4a.40.2'
    );
    check(
      'AUDIO_BITRATE',
      positive(metadata.audioBitrate) && metadata.audioBitrate <= 100800,
      metadata.audioBitrate,
      '<= 100800 bps'
    );
    check(
      'AUDIO_CHANNELS',
      metadata.audioChannels >= 1 && metadata.audioChannels <= 2,
      metadata.audioChannels,
      '1–2'
    );
    check(
      'AUDIO_RATE',
      metadata.audioSampleRate === 48000,
      metadata.audioSampleRate,
      '48000 Hz'
    );
  }
  return issues;
}

export async function inspectVideoExport(file, options) {
  const input = new Input({
    source: new BlobSource(file),
    formats: ALL_FORMATS,
  });
  try {
    const video = await input.getPrimaryVideoTrack();
    const audio = await input.getPrimaryAudioTrack();
    const tracks = await input.getTracks();
    if (tracks.some(track => track !== video && track !== audio))
      return {
        valid: false,
        issues: [
          {
            field: 'TRACKS',
            actual: tracks.length,
            expected: '1 video + 0–1 audio',
          },
        ],
      };
    if (!video)
      return {
        valid: false,
        issues: [{ field: 'VIDEO_TRACK', actual: false, expected: true }],
      };
    const stats = await video.computePacketStats();
    const audioStats = await audio?.computePacketStats();
    const audioConfig = await audio?.getDecoderConfig();
    const metadata = {
      mp4: await hasMp4FastStart(file),
      codec: await video.getCodec(),
      width: video.displayWidth,
      height: video.displayHeight,
      duration: await input.computeDuration(),
      frameRate: await inspectVideoFrameRate(video, stats),
      bitrate: stats.averageBitrate,
      hasAudio: !!audio,
      audioCodec: await audio?.getCodec(),
      audioBitrate: audioStats?.averageBitrate,
      audioChannels: await audio?.getNumberOfChannels(),
      audioSampleRate: await audio?.getSampleRate(),
    };
    const square = await hasExplicitSquarePixels(file);
    const rotation = await video.getRotation();
    const decoderConfig = await video.getDecoderConfig();
    const { fullRange, spsFullRange, declaredFullRange } =
      avcColorRange(decoderConfig);
    const avc420 = isAvc420(decoderConfig);
    const yuv420p = avc420 && fullRange === false;
    const valid =
      canKeepVideo(file, metadata, {
        quality: options.quality,
        maxOutputBytes: options.maxOutputBytes,
      }) &&
      square &&
      yuv420p &&
      rotation === 0 &&
      metadata.width % 2 === 0 &&
      metadata.height % 2 === 0 &&
      (!audio || audioConfig?.codec === 'mp4a.40.2');
    const result = {
      valid,
      ...metadata,
      square,
      rotation,
      yuv420p,
      fullRange,
      spsFullRange,
      declaredFullRange,
      avc420,
      audioProfile: audioConfig?.codec,
    };
    return { ...result, issues: videoExportIssues(result, options, file.size) };
  } finally {
    input.dispose();
  }
}
