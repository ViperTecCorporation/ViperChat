import { computed, onMounted, onUnmounted, ref, shallowRef, watch } from 'vue';
import { mergeMessages, request } from './api';

export function useAttendance(invitation) {
  const messages = ref([]);
  const name = ref('');
  const contactName = ref('');
  const state = ref('loading');
  const hasMore = ref(false);
  const loadingOlder = ref(false);
  const draft = ref('');
  const files = ref([]);
  const sending = ref(false);
  const error = ref('');
  const recording = ref(false);
  const startingRecording = ref(false);
  const voiceUrl = ref('');
  const recordingStream = shallowRef(null);
  const canRecord = computed(() =>
    Boolean(navigator.mediaDevices?.getUserMedia && window.MediaRecorder)
  );
  let token = invitation;
  const authenticated = ref(false);
  let polling = false;
  let timer;
  let disposed = false;
  let generation = 0;
  let requestId;
  let pageHidden = false;
  let presenceController;
  const presenceId = crypto.randomUUID();
  const acknowledgedStatuses = new Map();
  let recorder;
  let stream;
  let voiceFile;
  let recordingAttempt = 0;
  const controllers = new Set();

  function stopRecording() {
    if (recorder && recorder.state !== 'inactive') {
      startingRecording.value = true;
      recorder.stop();
    }
    stream?.getTracks().forEach(track => track.stop());
    stream = null;
    recording.value = false;
    recordingStream.value = null;
  }

  function cancelRecording() {
    recordingAttempt += 1;
    stopRecording();
    startingRecording.value = false;
  }

  function clearVoice() {
    if (voiceUrl.value) URL.revokeObjectURL(voiceUrl.value);
    voiceUrl.value = '';
    voiceFile = null;
  }

  function removeVoice() {
    files.value = files.value.filter(file => file !== voiceFile);
    clearVoice();
  }

  function revoke(status) {
    generation += 1;
    token = null;
    authenticated.value = false;
    state.value = status === 410 ? 'ended' : 'unavailable';
    messages.value = [];
    draft.value = '';
    files.value = [];
    name.value = '';
    contactName.value = '';
    error.value = '';
    clearTimeout(timer);
    cancelRecording();
    clearVoice();
    controllers.forEach(controller => controller.abort());
  }

  function handleError(exception, sendingMessage = false) {
    if (disposed) return;
    if ([410, 401, 403].includes(exception.status)) {
      revoke(exception.status);
    } else if (!['ended', 'unavailable'].includes(state.value)) {
      if (sendingMessage) {
        error.value = [400, 413, 422].includes(exception.status)
          ? 'rejected'
          : 'failed';
      } else {
        state.value = 'offline';
        acknowledgedStatuses.clear();
      }
    }
  }

  async function call(path, options) {
    const controller = new AbortController();
    controllers.add(controller);
    const currentGeneration = generation;
    try {
      const response = await request(path, {
        ...options,
        signal: controller.signal,
      });
      if (disposed || generation !== currentGeneration)
        throw new DOMException('Session closed', 'AbortError');
      return response;
    } finally {
      controllers.delete(controller);
    }
  }

  async function presence() {
    if (
      !authenticated.value ||
      disposed ||
      document.hidden ||
      pageHidden ||
      presenceController ||
      ['ended', 'unavailable'].includes(state.value)
    )
      return;
    const controller = new AbortController();
    presenceController = controller;
    controllers.add(controller);
    // Do not let a stalled heartbeat block polls or outlive backend freshness.
    const timeout = setTimeout(() => controller.abort(), 2500);
    try {
      await request('/presence', {
        method: 'POST',
        body: { visible: true, presence_id: presenceId },
        signal: controller.signal,
      });
    } catch (exception) {
      if (
        !controller.signal.aborted &&
        [401, 403, 410].includes(exception.status)
      ) {
        handleError(exception);
      }
      // Network failure is retried by the next poll, independently of read ACKs.
    } finally {
      clearTimeout(timeout);
      controllers.delete(controller);
      if (presenceController === controller) presenceController = null;
    }
  }

  function leave() {
    clearTimeout(timer);
    presenceController?.abort();
    presenceController = null;
    if (
      !authenticated.value ||
      disposed ||
      ['ended', 'unavailable'].includes(state.value)
    )
      return;
    // No token or abort signal: this cookie-authorized request must survive closing.
    request('/presence', {
      method: 'POST',
      keepalive: true,
      body: { visible: false, presence_id: presenceId },
    }).catch(() => {});
  }

  function pagehide() {
    pageHidden = true;
    leave();
  }

  async function seen() {
    if (document.hidden || pageHidden) return;
    const pending = messages.value.filter(message => {
      if (message.message_type !== 1) return false;
      if (message.status === 'read') acknowledgedStatuses.delete(message.id);
      return (
        ['sent', 'delivered', 'progress'].includes(message.status) &&
        acknowledgedStatuses.get(message.id) !== message.status
      );
    });
    if (!pending.length) return;
    try {
      await call('/seen', { method: 'POST' });
      pending.forEach(message =>
        acknowledgedStatuses.set(message.id, message.status)
      );
    } catch (exception) {
      handleError(exception);
    }
  }

  async function refresh() {
    if (polling || disposed || ['ended', 'unavailable'].includes(state.value))
      return;
    clearTimeout(timer);
    polling = true;
    try {
      if (token) {
        await call('/session', { method: 'POST', body: { token } });
        token = null;
      }
      const data = await call('/session');
      authenticated.value = true;
      name.value = data.name;
      contactName.value = data.contact_name;
      // Keep previously fetched pages when polling the newest page.
      if (!messages.value.length) hasMore.value = data.has_more;
      messages.value = mergeMessages(messages.value, data.messages || []);
      state.value = 'active';
      await seen();
    } catch (exception) {
      handleError(exception);
    } finally {
      polling = false;
      presence();
      if (
        !disposed &&
        !['ended', 'unavailable'].includes(state.value) &&
        !document.hidden &&
        !pageHidden
      )
        timer = setTimeout(refresh, 3000);
    }
  }

  async function older() {
    if (!authenticated.value || loadingOlder.value || !hasMore.value) return;
    loadingOlder.value = true;
    try {
      const oldest = messages.value[0]?.id;
      const data = await call(`/session?before=${encodeURIComponent(oldest)}`);
      messages.value = mergeMessages(messages.value, data.messages || []);
      hasMore.value = data.has_more;
      await seen();
    } catch (exception) {
      handleError(exception);
    } finally {
      loadingOlder.value = false;
    }
  }

  function addFiles(selected) {
    if (files.value.length + selected.length > 5) {
      error.value = 'limit';
      return;
    }
    files.value = [...files.value, ...selected];
    error.value = '';
  }

  function removeFile(index) {
    if (files.value[index] === voiceFile) clearVoice();
    files.value = files.value.filter((file, position) => position !== index);
  }

  async function send() {
    if (
      !authenticated.value ||
      sending.value ||
      recording.value ||
      startingRecording.value ||
      (!draft.value.trim() && !files.value.length)
    )
      return;
    sending.value = true;
    error.value = '';
    requestId ||= crypto.randomUUID();
    const form = new FormData();
    form.append('content', draft.value);
    form.append('request_id', requestId);
    files.value.forEach(file => form.append('attachments[]', file, file.name));
    try {
      const message = await call('/messages', { method: 'POST', body: form });
      // The POST must return the persisted presenter, including authorized media URLs.
      if (!message?.id) throw new Error('Missing persisted message');
      messages.value = mergeMessages(messages.value, [message]);
      draft.value = '';
      files.value = [];
      clearVoice();
      requestId = null;
      await refresh();
    } catch (exception) {
      handleError(exception, true);
    } finally {
      sending.value = false;
    }
  }

  async function startRecording() {
    if (
      !canRecord.value ||
      startingRecording.value ||
      recording.value ||
      sending.value ||
      voiceUrl.value ||
      files.value.length >= 5
    )
      return;
    startingRecording.value = true;
    recordingAttempt += 1;
    const attempt = recordingAttempt;
    error.value = '';
    try {
      const newStream = await navigator.mediaDevices.getUserMedia({
        audio: true,
      });
      if (
        disposed ||
        attempt !== recordingAttempt ||
        ['ended', 'unavailable'].includes(state.value)
      ) {
        newStream.getTracks().forEach(track => track.stop());
        return;
      }
      stream = newStream;
      const mimeType = [
        'audio/webm;codecs=opus',
        'audio/mp4',
        'audio/ogg;codecs=opus',
      ].find(type => MediaRecorder.isTypeSupported(type));
      recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined);
      const currentRecorder = recorder;
      const currentStream = stream;
      const chunks = [];
      recorder.ondataavailable = event => {
        if (event.data.size) chunks.push(event.data);
      };
      recorder.onstop = () => {
        currentStream.getTracks().forEach(track => track.stop());
        if (stream === currentStream) stream = null;
        if (attempt !== recordingAttempt) return;
        startingRecording.value = false;
        recording.value = false;
        recordingStream.value = null;
        if (
          disposed ||
          ['ended', 'unavailable'].includes(state.value) ||
          !chunks.length
        )
          return;
        const blob = new Blob(chunks, { type: currentRecorder.mimeType });
        const extensions = {
          'audio/mp4': 'm4a',
          'audio/ogg': 'ogg',
          'audio/webm': 'webm',
        };
        const extension = extensions[blob.type.split(';')[0]] || 'webm';
        const file = new File(
          [blob],
          `audio-${crypto.randomUUID()}.${extension}`,
          {
            type: blob.type,
          }
        );
        addFiles([file]);
        clearVoice();
        voiceFile = file;
        voiceUrl.value = URL.createObjectURL(blob);
      };
      recorder.onerror = () => {
        error.value = 'microphone';
        cancelRecording();
      };
      recorder.start();
      recording.value = true;
      recordingStream.value = stream;
    } catch {
      if (attempt !== recordingAttempt) return;
      error.value = 'microphone';
      cancelRecording();
    } finally {
      if (attempt === recordingAttempt) startingRecording.value = false;
    }
  }

  watch(
    [draft, files],
    () => {
      requestId = null;
    },
    { flush: 'sync' }
  );
  function resume() {
    if (document.hidden || pageHidden) leave();
    else {
      acknowledgedStatuses.clear();
      presence();
      refresh();
    }
  }
  function pageshow() {
    pageHidden = false;
    resume();
  }
  onMounted(() => {
    refresh();
    document.addEventListener('visibilitychange', resume);
    window.addEventListener('online', resume);
    window.addEventListener('pagehide', pagehide);
    window.addEventListener('pageshow', pageshow);
  });
  onUnmounted(() => {
    leave();
    disposed = true;
    clearTimeout(timer);
    controllers.forEach(controller => controller.abort());
    cancelRecording();
    clearVoice();
    document.removeEventListener('visibilitychange', resume);
    window.removeEventListener('online', resume);
    window.removeEventListener('pagehide', pagehide);
    window.removeEventListener('pageshow', pageshow);
  });
  return {
    authenticated,
    messages,
    name,
    contactName,
    state,
    hasMore,
    loadingOlder,
    draft,
    files,
    sending,
    error,
    recording,
    startingRecording,
    canRecord,
    voiceUrl,
    recordingStream,
    cancelRecording,
    removeVoice,
    refresh,
    older,
    send,
    addFiles,
    removeFile,
    startRecording,
    stopRecording,
  };
}
