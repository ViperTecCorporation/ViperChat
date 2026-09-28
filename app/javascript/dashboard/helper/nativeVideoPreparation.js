/* eslint-disable no-await-in-loop -- Bounded chunks avoid copying a 256 MiB video through the bridge. */
import { Capacitor, registerPlugin } from '@capacitor/core';
import { VIDEO_LIMIT } from './mediaProfiles';
import { inspectVideoExport } from './videoExportValidation';

const nativeVideo = registerPlugin('NativeVideo');
const CHUNK_SIZE = 512 * 1024;
export const usesNativeVideo = () =>
  Capacitor.isNativePlatform() && Capacitor.getPlatform() === 'ios';

function checkAbort(signal) {
  if (signal?.aborted) throw new DOMException('Canceled', 'AbortError');
}

function base64(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result.split(',')[1]);
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(blob);
  });
}

export async function prepareNativeVideo(
  file,
  options,
  { signal, onProgress = () => {} } = {}
) {
  checkAbort(signal);
  if (file.size > VIDEO_LIMIT) throw new Error('VIDEO_INPUT_TOO_LARGE');
  let id;
  let listener;
  const cancel = () => {
    if (id) nativeVideo.cancel({ id }).catch(() => {});
  };
  signal?.addEventListener('abort', cancel, { once: true });
  try {
    ({ id } = await nativeVideo.begin());
    checkAbort(signal);
    listener = await nativeVideo.addListener('progress', event => {
      if (event.id === id) onProgress(0.1 + event.progress * 0.8);
    });
    for (let offset = 0; offset < file.size; offset += CHUNK_SIZE) {
      checkAbort(signal);
      await nativeVideo.append({
        id,
        data: await base64(file.slice(offset, offset + CHUNK_SIZE)),
      });
      onProgress(Math.min(0.1, ((offset + CHUNK_SIZE) / file.size) * 0.1));
    }
    checkAbort(signal);
    const { size, error, diagnostic } = await nativeVideo.exportVideo({
      id,
      ...options,
    });
    checkAbort(signal);
    if (error) {
      throw Object.assign(new Error(error), {
        issues: [
          {
            field: 'NATIVE_EXPORT',
            actual: diagnostic,
            expected: 'MP4 / H.264 / AAC',
          },
        ],
      });
    }
    if (size > Math.min(VIDEO_LIMIT, options.maxOutputBytes || VIDEO_LIMIT))
      throw new Error('VIDEO_TOO_LARGE');
    const parts = [];
    for (let offset = 0; offset < size; offset += CHUNK_SIZE) {
      checkAbort(signal);
      const { data } = await nativeVideo.read({ id, offset });
      const bytes = Uint8Array.from(atob(data), char => char.charCodeAt(0));
      if (!bytes.length) throw new Error('INVALID_VIDEO');
      parts.push(bytes);
      onProgress(0.9 + Math.min(1, (offset + bytes.length) / size) * 0.09);
    }
    const result = new File(parts, file.name.replace(/\.[^.]+$/, '') + '.mp4', {
      type: 'video/mp4',
    });
    const validation = await inspectVideoExport(result, options);
    checkAbort(signal);
    if (!validation.valid) {
      throw Object.assign(new Error('VIDEO_EXPORT_NONCONFORMING'), {
        issues: validation.issues,
      });
    }
    onProgress(1);
    return result;
  } catch (error) {
    checkAbort(signal);
    throw error;
  } finally {
    signal?.removeEventListener('abort', cancel);
    try {
      await listener?.remove();
    } finally {
      if (id) await nativeVideo.dispose({ id });
    }
  }
}
