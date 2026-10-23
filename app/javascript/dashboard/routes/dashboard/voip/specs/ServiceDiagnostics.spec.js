import { mount, flushPromises } from '@vue/test-utils';
import ServiceDiagnostics from '../ServiceDiagnostics.vue';

const mocks = vi.hoisted(() => ({
  diagnostics: vi.fn(),
  reprocess: vi.fn(),
  recover: vi.fn(),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/voip', () => ({
  VoipAPI: vi.fn(function api(accountId) {
    return {
      diagnostics: serviceId => mocks.diagnostics(accountId, serviceId),
      reprocess: (...args) => mocks.reprocess(accountId, ...args),
      recoverHistory: (...args) => mocks.recover(accountId, ...args),
    };
  }),
}));

describe('Service diagnostics', () => {
  let wrapper;
  const data = {
    counts: {
      pending_events: 1,
      failed_events: 1,
      pending_artifacts: 2,
      failed_artifacts: 0,
    },
    records: [
      {
        kind: 'event',
        id: 10,
        state: 'retry',
        attempts: 2,
        last_error_code: 'transient_failure',
        next_attempt_at: '2026-10-22T12:10:00Z',
        created_at: '2026-10-22T12:00:00Z',
        reprocessable: true,
      },
    ],
    truncated: true,
    recovery: {
      state: 'retry',
      last_attempt_at: '2026-10-22T12:00:00Z',
      last_success_at: null,
      next_attempt_at: null,
      last_error_code: 'timeout',
      cursor_configured: true,
    },
  };
  const button = label =>
    wrapper
      .findAll('button')
      .find(item => item.text() === `AGENT_VOIP.DIAGNOSTICS.${label}`);
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.diagnostics.mockResolvedValue({ data });
    mocks.reprocess.mockResolvedValue({ data: { status: 'queued' } });
    mocks.recover.mockResolvedValue({ data: { status: 'queued' } });
    Object.defineProperty(HTMLDialogElement.prototype, 'showModal', {
      configurable: true,
      value() {
        this.setAttribute('open', '');
      },
    });
    Object.defineProperty(HTMLDialogElement.prototype, 'close', {
      configurable: true,
      value() {
        this.removeAttribute('open');
        this.dispatchEvent(new Event('close'));
      },
    });
  });
  afterEach(() => {
    wrapper?.unmount();
    vi.useRealTimers();
    delete HTMLDialogElement.prototype.showModal;
    delete HTMLDialogElement.prototype.close;
  });
  it('reads scoped diagnostics and displays counts, sanitized codes and recovery without payload', async () => {
    wrapper = mount(ServiceDiagnostics, {
      props: { accountId: 1, serviceId: 2 },
    });
    await flushPromises();
    expect(mocks.diagnostics).toHaveBeenCalledWith(1, 2);
    expect(wrapper.text()).toContain('transient_failure');
    expect(wrapper.text()).toContain('timeout');
    expect(wrapper.text()).toContain('CHECKPOINT_SAVED');
    expect(wrapper.text()).toContain('TRUNCATED');
    expect(wrapper.find('input').exists()).toBe(false);
    expect(mocks.reprocess).not.toHaveBeenCalled();
  });
  it('requires explicit modal confirmation before scoped retry', async () => {
    wrapper = mount(ServiceDiagnostics, {
      props: { accountId: 1, serviceId: 2 },
    });
    await flushPromises();
    await button('REPROCESS').trigger('click');
    expect(wrapper.find('dialog').attributes()).toHaveProperty('open');
    expect(mocks.reprocess).not.toHaveBeenCalled();
    await button('CONFIRM').trigger('click');
    await flushPromises();
    expect(mocks.reprocess).toHaveBeenCalledWith(1, 2, 'event', 10);
    expect(wrapper.text()).toContain('QUEUED');
    expect(wrapper.find('dialog').attributes()).not.toHaveProperty('open');
  });
  it('confirms history recovery separately and handles 409 without removing the warning', async () => {
    mocks.recover.mockRejectedValue({ response: { status: 409 } });
    wrapper = mount(ServiceDiagnostics, {
      props: { accountId: 1, serviceId: 2 },
    });
    await flushPromises();
    await button('RECOVER').trigger('click');
    expect(mocks.recover).not.toHaveBeenCalled();
    await button('CONFIRM').trigger('click');
    await flushPromises();
    expect(mocks.recover).toHaveBeenCalledWith(1, 2, { resetCursor: false });
    expect(wrapper.find('dialog [role="alert"]').text()).toContain('CONFLICT');
    expect(wrapper.find('dialog').attributes()).toHaveProperty('open');
  });
  it('excludes late diagnostics from a previous account', async () => {
    let resolveOld;
    mocks.diagnostics.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    wrapper = mount(ServiceDiagnostics, {
      props: { accountId: 1, serviceId: 2 },
    });
    mocks.diagnostics.mockResolvedValue({ data: { ...data, records: [] } });
    await wrapper.setProps({ accountId: 3, serviceId: 4 });
    await flushPromises();
    resolveOld({ data });
    await flushPromises();
    expect(wrapper.text()).not.toContain('transient_failure');
    expect(mocks.diagnostics).toHaveBeenLastCalledWith(3, 4);
  });
  it('requires an explicit opt-in to reset the recovery checkpoint without deleting history', async () => {
    wrapper = mount(ServiceDiagnostics, {
      props: { accountId: 1, serviceId: 2 },
    });
    await flushPromises();
    await button('RECOVER').trigger('click');
    expect(wrapper.find('input[type="checkbox"]').element.checked).toBe(false);
    await wrapper.find('input[type="checkbox"]').setValue(true);
    expect(wrapper.find('dialog').text()).toContain('RESET_CURSOR_HELP');
    await button('CONFIRM').trigger('click');
    await flushPromises();
    expect(mocks.recover).toHaveBeenCalledWith(1, 2, { resetCursor: true });
    expect(mocks.reprocess).not.toHaveBeenCalled();
  });
  it('does not apply a late retry response to the next account or leave its confirmation open', async () => {
    let resolveRetry;
    mocks.reprocess.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveRetry = resolve;
        })
    );
    wrapper = mount(ServiceDiagnostics, {
      props: { accountId: 1, serviceId: 2 },
    });
    await flushPromises();
    await button('REPROCESS').trigger('click');
    await button('CONFIRM').trigger('click');
    await wrapper.setProps({ accountId: 3, serviceId: 4 });
    await flushPromises();
    resolveRetry({ data: { status: 'queued' } });
    await flushPromises();
    expect(wrapper.find('dialog').attributes()).not.toHaveProperty('open');
    expect(wrapper.text()).not.toContain('DIAGNOSTICS.QUEUED');
    expect(mocks.reprocess).toHaveBeenCalledWith(1, 2, 'event', 10);
  });
  it('does not permit recovery for unsupported services or records without retry authorization', async () => {
    mocks.diagnostics.mockResolvedValue({
      data: {
        ...data,
        records: [{ ...data.records[0], reprocessable: false }],
        recovery: { ...data.recovery, state: 'unsupported' },
      },
    });
    wrapper = mount(ServiceDiagnostics, {
      props: { accountId: 1, serviceId: 2 },
    });
    await flushPromises();
    expect(button('RECOVER')).toBeUndefined();
    expect(button('REPROCESS')).toBeUndefined();
  });
  it('keeps incomplete recovery visible instead of claiming a complete history', async () => {
    mocks.diagnostics.mockResolvedValue({
      data: {
        ...data,
        recovery: {
          ...data.recovery,
          state: 'invalid_cursor',
          gap_detected: true,
          has_more: true,
        },
      },
    });
    wrapper = mount(ServiceDiagnostics, {
      props: { accountId: 1, serviceId: 2 },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('RECOVERY_STATE.invalid_cursor');
    expect(wrapper.text()).toContain('GAP_DETECTED');
    expect(wrapper.text()).toContain('HAS_MORE');
  });
  it('automatically releases the recovery button after a queued attempt finishes without resetting the checkpoint', async () => {
    vi.useFakeTimers();
    mocks.diagnostics.mockResolvedValueOnce({
      data: { ...data, recovery: { ...data.recovery, state: 'pending' } },
    });
    wrapper = mount(ServiceDiagnostics, {
      props: { accountId: 1, serviceId: 2 },
    });
    await flushPromises();
    expect(button('RECOVER').element.disabled).toBe(true);
    await vi.advanceTimersByTimeAsync(5000);
    await flushPromises();
    expect(button('RECOVER').element.disabled).toBe(false);
    expect(wrapper.text()).toContain('CHECKPOINT_SAVED');
    expect(mocks.diagnostics).toHaveBeenCalledTimes(2);
    expect(mocks.recover).not.toHaveBeenCalled();
    expect(mocks.reprocess).not.toHaveBeenCalled();
  });
  it('stops refreshing when the diagnostics modal is unmounted', async () => {
    vi.useFakeTimers();
    wrapper = mount(ServiceDiagnostics, {
      props: { accountId: 1, serviceId: 2 },
    });
    await flushPromises();
    wrapper.unmount();
    await vi.advanceTimersByTimeAsync(15000);
    expect(mocks.diagnostics).toHaveBeenCalledTimes(1);
  });
  it('does not refresh over a confirmation or discard its reset choice', async () => {
    vi.useFakeTimers();
    wrapper = mount(ServiceDiagnostics, {
      props: { accountId: 1, serviceId: 2 },
    });
    await flushPromises();
    await button('RECOVER').trigger('click');
    await wrapper.find('input[type="checkbox"]').setValue(true);
    await vi.advanceTimersByTimeAsync(10000);
    expect(mocks.diagnostics).toHaveBeenCalledTimes(1);
    expect(wrapper.find('input[type="checkbox"]').element.checked).toBe(true);
    expect(mocks.recover).not.toHaveBeenCalled();
    await wrapper
      .findAll('dialog button')
      .find(item => item.text() === 'AGENT_VOIP.CANCEL')
      .trigger('click');
    await vi.advanceTimersByTimeAsync(5000);
    await flushPromises();
    expect(mocks.diagnostics).toHaveBeenCalledTimes(2);
  });
  it('retries diagnostic reads after a network error without automatically recovering history', async () => {
    vi.useFakeTimers();
    mocks.diagnostics.mockRejectedValueOnce(new Error('offline'));
    wrapper = mount(ServiceDiagnostics, {
      props: { accountId: 1, serviceId: 2 },
    });
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    await vi.advanceTimersByTimeAsync(5000);
    await flushPromises();
    expect(button('RECOVER').element.disabled).toBe(false);
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(mocks.recover).not.toHaveBeenCalled();
  });
});
