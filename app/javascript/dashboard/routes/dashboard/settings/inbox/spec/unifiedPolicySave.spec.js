import Settings from '../Settings.vue';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/composables', async importOriginal => ({
  ...(await importOriginal()),
  useAlert: vi.fn(),
}));

describe('general inbox Update and linked policy', () => {
  const context = savePendingChanges => ({
    $refs: {
      whatsappUnifiedInbox: savePendingChanges
        ? { savePendingChanges }
        : undefined,
    },
    $store: { dispatch: vi.fn().mockResolvedValue({}) },
    $t: key => key,
    inbox: {},
    currentInboxId: 1,
    selectedInboxName: 'Viper Tec',
    widgetBuilderStorageKey: 'test-unified-policy',
  });

  beforeEach(() => vi.clearAllMocks());

  it('waits for policy persistence before reporting successful Update', async () => {
    const save = vi.fn().mockResolvedValue();
    const vm = context(save);
    await Settings.methods.updateInbox.call(vm);
    expect(save).toHaveBeenCalledOnce();
    expect(vm.$store.dispatch).toHaveBeenCalledOnce();
    expect(save.mock.invocationCallOrder[0]).toBeLessThan(
      vm.$store.dispatch.mock.invocationCallOrder[0]
    );
    expect(useAlert).toHaveBeenCalledWith(
      'INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'
    );
  });

  it.each([
    new Error('Network failure'),
    Object.assign(new Error('review'), {
      code: 'whatsapp_link_review_required',
    }),
  ])(
    'does not report success if the policy could not be saved: %s',
    async error => {
      const vm = context(vi.fn().mockRejectedValue(error));
      await Settings.methods.updateInbox.call(vm);
      expect(vm.$store.dispatch).not.toHaveBeenCalled();
      expect(useAlert).toHaveBeenCalledWith(
        error.code ? 'WHATSAPP_UNIFIED.SAVE_REVIEW_REQUIRED' : error.message
      );
    }
  );

  it('keeps ordinary inbox updates independent of linked inboxes', async () => {
    const vm = context();
    await Settings.methods.updateInbox.call(vm);
    expect(vm.$store.dispatch).toHaveBeenCalledOnce();
    expect(useAlert).toHaveBeenCalledWith(
      'INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'
    );
  });
});
