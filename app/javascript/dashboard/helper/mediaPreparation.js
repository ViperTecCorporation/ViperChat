import { prepareNativeVideo, usesNativeVideo } from './nativeVideoPreparation';

export function prepareVideo(
  file,
  options,
  { signal, onProgress = () => {}, onNotice = () => {} } = {}
) {
  if (usesNativeVideo())
    return prepareNativeVideo(file, options, { signal, onProgress, onNotice });
  return new Promise((resolve, reject) => {
    const worker = new Worker(
      new URL('./mediaPreparation.worker.js', import.meta.url),
      { type: 'module' }
    );
    const finish = (fn, value) => {
      // eslint-disable-next-line no-use-before-define -- Cancel is registered after both closures are initialized.
      signal?.removeEventListener('abort', cancel);
      worker.terminate();
      fn(value);
    };
    function cancel() {
      finish(reject, new DOMException('Canceled', 'AbortError'));
    }
    if (signal?.aborted) {
      cancel();
      return;
    }
    signal?.addEventListener('abort', cancel, { once: true });
    worker.onmessage = ({ data }) => {
      if (data.notice) onNotice(data.notice);
      else if (data.progress !== undefined) onProgress(data.progress);
      else if (data.error)
        finish(
          reject,
          Object.assign(new Error(data.error), { issues: data.issues })
        );
      else
        finish(
          resolve,
          data.original
            ? file
            : new File(
                [data.buffer],
                file.name.replace(/\.[^.]+$/, '') + '.mp4',
                { type: 'video/mp4' }
              )
        );
    };
    worker.onerror = () => finish(reject, new Error('VIDEO_UNSUPPORTED'));
    worker.postMessage({ file, options });
  });
}

export async function prepareImage(file, quality = 'hd') {
  const bitmap = await createImageBitmap(file);
  try {
    const edge = quality === 'sd' ? 1600 : 2560;
    const scale = Math.min(1, edge / Math.max(bitmap.width, bitmap.height));
    if (
      scale === 1 &&
      file.size <= 4 * 1024 * 1024 &&
      file.type !== 'image/webp'
    )
      return file;
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(bitmap.width * scale));
    canvas.height = Math.max(1, Math.round(bitmap.height * scale));
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = '#fff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise(resolve => {
      canvas.toBlob(resolve, 'image/jpeg', quality === 'sd' ? 0.8 : 0.9);
    });
    if (!blob) throw new Error('IMAGE_ERROR');
    return new File([blob], file.name.replace(/\.[^.]+$/, '') + '.jpg', {
      type: 'image/jpeg',
    });
  } finally {
    bitmap.close();
  }
}
