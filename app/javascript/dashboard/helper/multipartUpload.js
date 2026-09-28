/* global axios */
/* eslint-disable no-await-in-loop -- Each bounded worker uploads one part at a time; retries must be sequential. */
import { reactive } from 'vue';
import { DirectUpload as ActiveStorageUpload } from 'activestorage';
import { FileChecksum } from 'activestorage/src/file_checksum';
import { getDirectUploadUrl } from './directUploadsHelper';

export const MULTIPART_THRESHOLD = 64 * 1024 * 1024;
export const multipartUploads = reactive([]);
export const needsMultipart = file => file?.size >= MULTIPART_THRESHOLD;

const checksum = file =>
  new Promise((resolve, reject) => {
    FileChecksum.create(file, (error, value) =>
      error ? reject(new Error(error)) : resolve(value)
    );
  });

const canceled = () => new DOMException('Upload cancelled', 'AbortError');

async function retryPart(action, signal) {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    if (signal.aborted) throw canceled();
    try {
      return await action();
    } catch (error) {
      const status = error.response?.status || error.status;
      if (
        signal.aborted ||
        attempt === 2 ||
        (status >= 400 && status < 500 && status !== 408 && status !== 429)
      )
        throw error;
      await new Promise(resolve => {
        setTimeout(resolve, 500 * 2 ** attempt);
      });
    }
  }
  return undefined;
}

// No application/auth headers are sent to the presigned storage origin.
function putPart(url, headers, body, signal, progress) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    const abort = () => xhr.abort();
    xhr.open('PUT', url);
    xhr.timeout = 120000;
    Object.entries(headers).forEach(([name, value]) =>
      xhr.setRequestHeader(name, value)
    );
    xhr.upload.onprogress = event => progress(event.loaded);
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) resolve();
      else
        reject(
          Object.assign(new Error('Part upload failed'), { status: xhr.status })
        );
    };
    xhr.onerror = () => reject(new Error('Part upload failed'));
    xhr.ontimeout = xhr.onerror;
    xhr.onabort = () => reject(canceled());
    xhr.onloadend = () => signal.removeEventListener('abort', abort);
    signal.addEventListener('abort', abort, { once: true });
    if (signal.aborted) reject(canceled());
    else xhr.send(body);
  });
}

export class DirectUpload {
  constructor(file, url, delegate) {
    this.file = file;
    this.url = url;
    this.delegate = delegate;
    this.controller = new AbortController();
  }

  abort() {
    this.controller.abort();
  }

  create(callback) {
    if (!needsMultipart(this.file)) {
      return new ActiveStorageUpload(this.file, this.url, this.delegate).create(
        callback
      );
    }
    return this.run().then(
      blob => {
        if (blob) callback(null, blob);
        else if (this.delegate?.indirect) callback(null, null);
        else
          new ActiveStorageUpload(this.file, this.url, this.delegate).create(
            callback
          );
      },
      error => callback(error.message)
    );
  }

  async run() {
    const accountId =
      this.url.match(/\/accounts\/(\d+)/)?.[1] ||
      window.location.pathname.match(/\/accounts\/(\d+)/)?.[1] ||
      window.viperNativeAccountId;
    if (!accountId) throw new Error('Missing upload account');
    const conversationId = this.url.match(/\/conversations\/(\d+)/)?.[1];
    const base = getDirectUploadUrl(
      `/api/v1/accounts/${accountId}/multipart_uploads`
    );
    const { data: capabilities } = await axios.get(base, {
      timeout: 15000,
      signal: this.controller.signal,
    });
    if (!capabilities.supported) return null;

    const state = reactive({
      id: Symbol('upload'),
      name: this.file.name,
      percent: 0,
      phase: 'PREPARING',
      cancel: () => this.abort(),
    });
    multipartUploads.push(state);
    this.delegate?.onUploadProgress?.({ phase: state.phase, percent: null });
    let sessionUrl;
    const { signal } = this.controller;
    try {
      const digest = await checksum(this.file);
      if (signal.aborted) throw canceled();
      // Do not abort initiation: if the response arrives after cancellation, use
      // its token to abort remotely. A lost response is covered by server cleanup.
      const { data: session } = await axios.post(
        base,
        {
          conversation_id: conversationId,
          blob: {
            filename: this.file.name,
            byte_size: this.file.size,
            content_type: this.file.type || 'application/octet-stream',
            checksum: digest,
          },
        },
        { timeout: 30000 }
      );
      sessionUrl = `${base}/${encodeURIComponent(session.token)}`;
      state.phase = 'UPLOADING';
      this.delegate?.onUploadProgress?.({ phase: state.phase, percent: 0 });
      await this.uploadParts(sessionUrl, session, state);
      if (signal.aborted) throw canceled();
      state.phase = 'COMPLETING';
      this.delegate?.onUploadProgress?.({ phase: state.phase, percent: null });
      // Completion is idempotent; losing its response must not restart the file.
      const { data: blob } = await retryPart(
        () => axios.post(`${sessionUrl}/complete`, null, { timeout: 120000 }),
        signal
      );
      if (signal.aborted) throw canceled();
      return blob;
    } catch (error) {
      this.controller.abort();
      if (sessionUrl) {
        // Cleanup has a bounded server-side backup for closed tabs/network loss.
        await axios.delete(sessionUrl, { timeout: 15000 }).catch(() => {});
      }
      state.phase =
        error.name === 'AbortError' || error.code === 'ERR_CANCELED'
          ? 'CANCELLED'
          : 'FAILED';
      state.cancel = () =>
        multipartUploads.splice(multipartUploads.indexOf(state), 1);
      throw error;
    } finally {
      if (!['FAILED', 'CANCELLED'].includes(state.phase))
        multipartUploads.splice(multipartUploads.indexOf(state), 1);
    }
  }

  async uploadParts(url, session, state) {
    const { signal } = this.controller;
    const count = Math.ceil(this.file.size / session.part_size);
    const loaded = new Array(count).fill(0);
    let next = 0;
    let firstFailure;
    const worker = async () => {
      while (next < count) {
        if (signal.aborted) throw canceled();
        const index = next;
        next += 1;
        const part = this.file.slice(
          index * session.part_size,
          (index + 1) * session.part_size
        );
        const md5 = await checksum(part);
        const params = { part_number: index + 1, checksum: md5 };
        const progress = bytes => {
          loaded[index] = Math.min(bytes, part.size);
          state.percent = Math.floor(
            (loaded.reduce((sum, value) => sum + value, 0) * 100) /
              this.file.size
          );
          this.delegate?.onUploadProgress?.({
            phase: 'UPLOADING',
            percent: state.percent,
            loaded: loaded.reduce((sum, value) => sum + value, 0),
            total: this.file.size,
          });
        };
        await retryPart(async () => {
          if (session.direct) {
            const { data } = await axios.post(`${url}/part`, params, {
              signal,
              timeout: 30000,
            });
            await putPart(data.url, data.headers, part, signal, progress);
          } else {
            const form = new FormData();
            form.append('file', part, 'part');
            Object.entries(params).forEach(([key, value]) =>
              form.append(key, value)
            );
            await axios.put(`${url}/part`, form, {
              signal,
              timeout: 120000,
              onUploadProgress: event => progress(event.loaded),
            });
          }
          progress(part.size);
        }, signal);
      }
    };
    const workers = Array.from({ length: Math.min(3, count) }, () =>
      worker().catch(error => {
        firstFailure ||= error;
        this.controller.abort();
        throw error;
      })
    );
    // Wait for in-flight requests to stop before aborting the remote upload.
    await Promise.allSettled(workers);
    if (firstFailure) throw firstFailure;
  }
}
