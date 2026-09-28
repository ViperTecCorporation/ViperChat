import mixin from 'dashboard/mixins/mediaEditorMixin';
import { DirectUpload, needsMultipart } from 'dashboard/helper/multipartUpload';
vi.mock('dashboard/helper/multipartUpload', () => ({
  DirectUpload: vi.fn(),
  needsMultipart: vi.fn(() => false),
}));
vi.mock('dashboard/helper/directUploadsHelper', () => ({
  getDirectUploadUrl: url => url,
  setDirectUploadAuthHeaders: vi.fn(),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('@chatwoot/utils', () => ({
  getUndefinedVariablesInMessage: () => [],
}));
const file = new File(['image'], 'test.jpg', { type: 'image/jpeg' });
const makeVm = () => {
  const session = {
    conversationId: 9,
    accountId: 1,
    caption: 'Initial',
    reply: { id: 123 },
    consumed: false,
  };
  return {
    mediaEditorSession: session,
    currentChat: { id: 9 },
    accountId: 1,
    isPrivate: false,
    isEditorDisabled: false,
    isReplyRestricted: false,
    showFileUpload: true,
    globalConfig: { directUploadsEnabled: false },
    maxSizeFor: () => 40,
    sender: { id: 7 },
    message: 'Initial',
    removeFromDraft: vi.fn(),
    resetReplyToMessage: vi.fn(),
    withGroupMentionsInPayload: payload => payload,
    $store: { dispatch: vi.fn().mockResolvedValue({}) },
    $t: key => key,
  };
};
describe('editor upload and message integration', () => {
  it('forwards multipart and direct XHR progress to the editor', async () => {
    const vm = makeVm();
    const onProgress = vi.fn();
    vm.globalConfig.directUploadsEnabled = true;
    DirectUpload.mockImplementation((_file, _url, delegate) => ({
      create: callback => {
        delegate.onUploadProgress({ phase: 'UPLOADING', percent: 25 });
        const upload = new EventTarget();
        delegate.directUploadWillStoreFileWithXHR({ upload });
        upload.dispatchEvent(
          new ProgressEvent('progress', { loaded: 50, total: 100 })
        );
        callback(null, { signed_id: 'uploaded' });
      },
    }));
    await mixin.methods.submitEditedMedia.call(vm, file, '', { onProgress });
    expect(onProgress).toHaveBeenCalledWith({
      phase: 'UPLOADING',
      percent: 25,
    });
    expect(onProgress).toHaveBeenCalledWith({
      phase: 'UPLOADING',
      percent: 50,
      loaded: 50,
      total: 100,
    });
    expect(onProgress).toHaveBeenLastCalledWith({
      phase: 'COMPLETING',
      percent: null,
    });
  });
  it.each(['sd', 'hd'])(
    'keeps video quality %s with the quote through upload',
    async quality => {
      const vm = makeVm();
      vm.isAUnoapiChannel = true;
      vm.globalConfig.directUploadsEnabled = true;
      DirectUpload.mockImplementation(() => ({
        create: callback => callback(null, { signed_id: 'video-blob' }),
      }));
      const video = new File(['video'], 'clip.mp4', { type: 'video/mp4' });
      await mixin.methods.submitEditedMedia.call(vm, video, 'Caption', {
        videoQuality: quality,
      });
      expect(vm.$store.dispatch.mock.calls[0][1]).toMatchObject({
        files: ['video-blob'],
        contentAttributes: { in_reply_to: 123, video_quality: quality },
      });
    }
  );
  it('does not add ViperConnect video quality to images or other providers', async () => {
    const vm = makeVm();
    vm.isAUnoapiChannel = true;
    await mixin.methods.submitEditedMedia.call(vm, file, '', {
      videoQuality: 'hd',
    });
    expect(vm.$store.dispatch.mock.calls[0][1].contentAttributes).toEqual({
      in_reply_to: 123,
    });
    vm.isAUnoapiChannel = false;
    await mixin.methods.submitEditedMedia.call(
      vm,
      new File(['v'], 'v.mp4', { type: 'video/mp4' }),
      '',
      { videoQuality: 'sd' }
    );
    expect(vm.$store.dispatch.mock.calls[1][1].contentAttributes).toEqual({
      in_reply_to: 123,
    });
  });
  beforeEach(() => {
    vi.clearAllMocks();
    needsMultipart.mockReturnValue(false);
  });
  it('uses the existing indirect message upload with caption, quote and one dispatch', async () => {
    const vm = makeVm();
    const result = await mixin.methods.submitEditedMedia.call(
      vm,
      file,
      'Caption'
    );
    expect(result).toEqual({ ok: true, dispatched: true });
    expect(DirectUpload).not.toHaveBeenCalled();
    expect(vm.$store.dispatch).toHaveBeenCalledWith(
      'sendMessageWithData',
      expect.objectContaining({
        files: [file],
        content: 'Caption',
        conversation_id: 9,
        contentAttributes: { in_reply_to: 123 },
      })
    );
    expect(vm.message).toBe('');
  });
  it.each([true, false])(
    'uses signed blob with direct=%s and multipart fallback',
    async direct => {
      const vm = makeVm();
      vm.globalConfig.directUploadsEnabled = direct;
      needsMultipart.mockReturnValue(!direct);
      DirectUpload.mockImplementation(() => ({
        create: callback => callback(null, { signed_id: 'signed-test' }),
      }));
      await mixin.methods.submitEditedMedia.call(vm, file, 'Caption');
      expect(vm.$store.dispatch.mock.calls[0][1].files).toEqual([
        'signed-test',
      ]);
      expect(DirectUpload.mock.calls[0][2].indirect).toBe(!direct);
    }
  );
  it('does not dispatch after upload failure and keeps the draft', async () => {
    const vm = makeVm();
    vm.globalConfig.directUploadsEnabled = true;
    DirectUpload.mockImplementation(() => ({
      create: callback => callback(new Error('failed')),
    }));
    expect(await mixin.methods.submitEditedMedia.call(vm, file, '')).toEqual({
      ok: false,
      dispatched: false,
    });
    expect(vm.$store.dispatch).not.toHaveBeenCalled();
    expect(vm.message).toBe('Initial');
  });
  it('does not send if conversation changed during upload', async () => {
    const vm = makeVm();
    vm.globalConfig.directUploadsEnabled = true;
    DirectUpload.mockImplementation(() => ({
      create: callback => {
        vm.currentChat.id = 10;
        callback(null, { signed_id: 'signed-test' });
      },
    }));
    expect(await mixin.methods.submitEditedMedia.call(vm, file, '')).toEqual({
      ok: false,
      dispatched: false,
    });
    expect(vm.$store.dispatch).not.toHaveBeenCalled();
  });
  it('rejects another account even with the same conversation display ID', async () => {
    const vm = makeVm();
    vm.accountId = 2;
    await mixin.methods.submitEditedMedia.call(vm, file, '');
    expect(vm.$store.dispatch).not.toHaveBeenCalled();
  });
  it('leaves a failed dispatch to the bubble retry and never dispatches twice', async () => {
    const vm = makeVm();
    vm.$store.dispatch.mockRejectedValue(new Error('network'));
    expect(await mixin.methods.submitEditedMedia.call(vm, file, '')).toEqual({
      ok: false,
      dispatched: true,
    });
    expect(vm.$store.dispatch).toHaveBeenCalledTimes(1);
  });
});
