/* eslint-disable no-restricted-globals, no-await-in-loop, no-continue -- Dedicated worker with one bounded bitrate retry. */
import {
  Input,
  BlobSource,
  ALL_FORMATS,
  MP4,
  Output,
  BufferTarget,
  Mp4OutputFormat,
  Conversion,
  Quality,
  canEncodeAudio,
} from 'mediabunny';
import { videoProfile, canKeepVideo, VIDEO_LIMIT } from './mediaProfiles';
import { hasMp4FastStart } from './mp4FastStart';
import { inspectVideoExport } from './videoExportValidation';
import { inspectVideoFrameRate } from './videoFrameRate';
import { limitedRangeProcessor } from './videoColorRange';

self.onmessage = async ({ data: { file, options } }) => {
  let input;
  try {
    if (file.size > VIDEO_LIMIT) throw new Error('VIDEO_INPUT_TOO_LARGE');
    input = new Input({ source: new BlobSource(file), formats: ALL_FORMATS });
    const video = await input.getPrimaryVideoTrack();
    const audio = await input.getPrimaryAudioTrack();
    if (!video) throw new Error('INVALID_VIDEO');
    const duration = await input.computeDuration();
    const stats = await video.computePacketStats();
    const audioStats = audio ? await audio.computePacketStats() : null;
    const audioChannels = audio ? await audio.getNumberOfChannels() : 0;
    const metadata = {
      mp4: (await input.getFormat()) === MP4,
      codec: await video.getCodec(),
      audioCodec: await audio?.getCodec(),
      duration,
      width: video.displayWidth,
      height: video.displayHeight,
      frameRate: await inspectVideoFrameRate(video, stats),
      bitrate: stats.averageBitrate,
      hasAudio: !!audio,
      audioBitrate: audioStats?.averageBitrate,
      audioChannels,
      audioSampleRate: audio ? await audio.getSampleRate() : null,
    };
    if (
      canKeepVideo(file, metadata, options) &&
      (await hasMp4FastStart(file)) &&
      (await inspectVideoExport(file, options)).valid
    ) {
      self.postMessage({ original: true });
      return;
    }
    const start = Number(options.start || 0);
    const end = Number(options.end || duration);
    if (start < 0 || end > duration + 0.05 || end <= start)
      throw new Error('INVALID_VIDEO');
    const profile = videoProfile(
      video.displayWidth,
      video.displayHeight,
      end - start,
      options.quality,
      options.mute || !audio
    );
    let targetBitrate = Math.floor(profile.bitrate * 0.8);
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const output = new Output({
        format: new Mp4OutputFormat({ fastStart: 'in-memory' }),
        target: new BufferTarget(),
      });
      const audioSettings = {
        codec: 'aac',
        numberOfChannels: Math.max(1, Math.min(2, audioChannels)),
        sampleRate: 48000,
        quality: new Quality({ bitrate: profile.audioBitrate || 96000 }),
      };
      if (
        audio &&
        !options.mute &&
        profile.audioBitrate === 64000 &&
        !(await canEncodeAudio('aac', audioSettings))
      ) {
        audioSettings.quality = new Quality({ bitrate: 96000 });
        if (!(await canEncodeAudio('aac', audioSettings)))
          throw new Error('VIDEO_UNSUPPORTED');
        self.postMessage({ notice: 'AUDIO_BITRATE_FALLBACK' });
      }
      const conversion = await Conversion.init({
        input,
        output,
        trim: { start, end },
        video: {
          codec: 'avc',
          width: profile.width,
          height: profile.height,
          fit: 'contain',
          // Normalize actual frame timestamps, including VFR bursts above 30.
          frameRate: Math.min(30, metadata.frameRate),
          quality: new Quality({
            // Android VBR minimum-quality rules can raise the requested bitrate.
            // Use CBR with headroom, and still verify the actual encoded stream.
            bitrate: targetBitrate,
            bitrateMode: 'constant',
          }),
          allowTransformationMetadata: false,
          forceTranscode: true,
          process: limitedRangeProcessor(profile.width, profile.height),
        },
        audio: options.mute || !audio ? { discard: true } : audioSettings,
      });
      if (
        !conversion.isValid ||
        conversion.discardedTracks.some(
          track => track.reason !== 'discarded_by_user'
        )
      ) {
        throw new Error('VIDEO_UNSUPPORTED');
      }
      conversion.onProgress = progress => self.postMessage({ progress });
      await conversion.execute();
      const buffer = output.target.buffer;
      if (
        !buffer ||
        buffer.byteLength >
          Math.min(VIDEO_LIMIT, options.maxOutputBytes || VIDEO_LIMIT)
      )
        throw new Error('VIDEO_TOO_LARGE');
      const validation = await inspectVideoExport(
        new Blob([buffer], { type: 'video/mp4' }),
        options
      );
      if (!validation.valid) {
        if (attempt === 0 && validation.bitrate > profile.bitrate) {
          targetBitrate = Math.max(
            Math.floor(profile.bitrate * 0.25),
            Math.floor(
              targetBitrate - (validation.bitrate - profile.bitrate) * 1.35
            )
          );
          self.postMessage({ notice: 'VIDEO_BITRATE_RETRY' });
          continue;
        }
        throw Object.assign(new Error('VIDEO_EXPORT_NONCONFORMING'), {
          issues: validation.issues,
        });
      }
      self.postMessage({ buffer }, [buffer]);
      return;
    }
  } catch (error) {
    self.postMessage({
      ...(error.issues ? { issues: error.issues } : {}),
      error: [
        'INVALID_VIDEO',
        'VIDEO_INPUT_TOO_LARGE',
        'VIDEO_TOO_LARGE',
        'VIDEO_EXPORT_NONCONFORMING',
      ].includes(error.message)
        ? error.message
        : 'VIDEO_UNSUPPORTED',
    });
  } finally {
    input?.dispose();
  }
};
