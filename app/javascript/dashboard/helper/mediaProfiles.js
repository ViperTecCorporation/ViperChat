// Editor/worker input ceiling, not a universal WhatsApp output limit.
export const VIDEO_LIMIT = 256 * 1024 * 1024;
export const MEDIA_LIMIT = 20;
export function formatMediaTime(value) {
  const seconds = Number.isFinite(Number(value))
    ? Math.max(0, Math.floor(Number(value)))
    : 0;
  const minutes = Math.floor(seconds / 60);
  return `${String(minutes).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;
}
export const isEditableMedia = file =>
  /^(image\/(jpeg|png|webp)|video\/(mp4|quicktime|webm|x-matroska))$/i.test(
    file?.type || ''
  );

export function videoProfile(
  width,
  height,
  duration,
  quality = 'hd',
  mute = false
) {
  if (![width, height, duration].every(n => Number.isFinite(n) && n > 0))
    throw new Error('INVALID_VIDEO');
  const longEdge = quality === 'sd' ? 854 : 1280;
  const shortEdge = quality === 'sd' ? 480 : 720;
  const scale = Math.min(
    1,
    longEdge / Math.max(width, height),
    shortEdge / Math.min(width, height)
  );
  const profileAudioBitrate = quality === 'sd' ? 64000 : 96000;
  const audioBitrate = mute ? 0 : profileAudioBitrate;
  const bitrate = quality === 'sd' ? 1200000 : 2500000;
  return {
    width: Math.max(2, Math.floor((width * scale) / 2) * 2),
    height: Math.max(2, Math.floor((height * scale) / 2) * 2),
    bitrate,
    audioBitrate,
  };
}

export function canKeepVideo(file, metadata, options) {
  if (
    ![
      metadata.width,
      metadata.height,
      metadata.duration,
      metadata.frameRate,
      metadata.bitrate,
    ].every(n => Number.isFinite(n) && n > 0)
  )
    return false;
  const profile = videoProfile(
    metadata.width,
    metadata.height,
    metadata.duration,
    options.quality,
    !metadata.hasAudio
  );
  return (
    metadata.mp4 &&
    metadata.codec === 'avc' &&
    (!metadata.hasAudio ||
      (metadata.audioCodec === 'aac' &&
        metadata.audioBitrate > 0 &&
        metadata.audioBitrate <= 96000 * 1.05 &&
        metadata.audioChannels >= 1 &&
        metadata.audioChannels <= 2 &&
        metadata.audioSampleRate === 48000)) &&
    file.size <= Math.min(VIDEO_LIMIT, options.maxOutputBytes || VIDEO_LIMIT) &&
    metadata.width <= profile.width &&
    metadata.height <= profile.height &&
    metadata.frameRate <= 30 &&
    metadata.bitrate <= profile.bitrate &&
    !options.mute &&
    !options.start &&
    (!options.end || Math.abs(options.end - metadata.duration) < 0.05)
  );
}
