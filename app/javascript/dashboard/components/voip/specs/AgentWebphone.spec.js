import { mount, flushPromises } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import { createRouter, createMemoryHistory } from 'vue-router';
import AgentWebphone from '../AgentWebphone.vue';

const mocks = vi.hoisted(() => ({ phone: null, resize: null, desktop: null }));
vi.mock('dashboard/stores/agentVoip', () => ({
  useAgentVoipStore: () => mocks.phone,
}));
vi.mock('dashboard/api/voip', () => ({
  VoipAPI: class {
    directory = vi.fn().mockResolvedValue({
      data: {
        items: [{ id: 2, name: 'Test operator', address: '1002' }],
        total: 1,
      },
    });
  },
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: ref(1) }),
}));
vi.mock('@vueuse/core', async () => ({
  ...(await vi.importActual('@vueuse/core')),
  useMediaQuery: () => mocks.desktop,
  useResizeObserver: (target, callback) => {
    mocks.resize = callback;
  },
}));

describe('Global draggable agent webphone', () => {
  let wrapper;
  let frames;

  beforeEach(() => {
    mocks.desktop = ref(true);
    frames = new WeakMap();
    vi.stubGlobal('innerWidth', 1280);
    vi.stubGlobal('innerHeight', 900);
    vi.stubGlobal('visualViewport', undefined);
    vi.stubGlobal('PointerEvent', MouseEvent);
    vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
      function bounds() {
        const frame = frames.get(this) || {};
        const offsets = /translate\(([-.\d]+)px, ([-.\d]+)px\)/.exec(
          frame.transform || ''
        );
        const width = Math.min(384, window.innerWidth - 32);
        const height = Math.min(200, parseFloat(frame.maxHeight) || 200);
        return {
          left: window.innerWidth - width - 16 + Number(offsets?.[1] || 0),
          top: window.innerHeight - height - 16 + Number(offsets?.[2] || 0),
          width,
          height,
        };
      }
    );
    Element.prototype.animate = vi.fn(function animate(values) {
      const element = this;
      frames.set(element, values[0]);
      return {
        cancel: vi.fn(() => frames.delete(element)),
        effect: { setKeyframes: next => frames.set(element, next[0]) },
      };
    });
    Element.prototype.setPointerCapture = vi.fn();
    mocks.phone = reactive({
      call: { state: 'active', direction: 'outgoing', remote_address: '1002' },
      activeBinding: { service_name: 'Central', extension: '1001' },
      activeService: { id: 1, transfer_enabled: true },
      expanded: true,
      muted: false,
      error: '',
      historyPending: false,
      prepare: vi.fn().mockResolvedValue(),
      refreshConfiguration: vi.fn(),
      stop: vi.fn(),
      toggleMute: vi.fn(),
      hangup: vi.fn(),
      transfer: vi.fn().mockResolvedValue(),
    });
  });

  afterEach(() => {
    wrapper?.unmount();
    delete Element.prototype.animate;
    delete Element.prototype.setPointerCapture;
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it('teleports outside the routed page and keeps the same call across navigation', async () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/calls', component: { template: '<p>Calls page</p>' } },
        { path: '/contacts', component: { template: '<p>Contacts page</p>' } },
      ],
    });
    await router.push('/calls');
    wrapper = mount(
      {
        components: { AgentWebphone },
        template: '<RouterView/><AgentWebphone/>',
      },
      { global: { plugins: [router] } }
    );
    await flushPromises();
    const panel = document.body.querySelector('aside[aria-label="Calls"]');
    expect(panel).not.toBeNull();
    expect(wrapper.element.contains(panel)).toBe(false);
    await router.push('/contacts');
    await flushPromises();
    expect(wrapper.text()).toContain('Contacts page');
    expect(document.body.querySelector('aside[aria-label="Calls"]')).toBe(
      panel
    );
    expect(mocks.phone.stop).not.toHaveBeenCalled();
    expect(mocks.phone.prepare).toHaveBeenCalledOnce();
  });

  it('selects another operator in the full-screen mobile webphone and requires explicit transfer', async () => {
    mocks.desktop.value = false;
    wrapper = mount(AgentWebphone);
    await flushPromises();
    const panel = document.body.querySelector('aside');
    panel.querySelector('button[aria-label="Transfer to extension"]').click();
    await flushPromises();
    panel.querySelector('li button').click();
    await flushPromises();
    expect(mocks.phone.transfer).not.toHaveBeenCalled();
    panel
      .querySelector('form')
      .dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    await flushPromises();
    expect(mocks.phone.transfer).toHaveBeenCalledWith('1002');
    expect(panel.classList.contains('inset-0')).toBe(true);
  });

  it('drags only from the header and clamps the window inside the viewport', async () => {
    wrapper = mount(AgentWebphone);
    await flushPromises();
    const panel = document.body.querySelector('aside');
    const handle = panel.querySelector('button[aria-label^="Move webphone"]');
    handle.dispatchEvent(
      Object.assign(new Event('pointerdown', { bubbles: true }), {
        button: 0,
        isPrimary: true,
        pointerId: 1,
        clientX: 100,
        clientY: 100,
      })
    );
    handle.dispatchEvent(
      Object.assign(new Event('pointermove', { bubbles: true }), {
        pointerId: 1,
        clientX: -5000,
        clientY: -5000,
      })
    );
    expect(panel.getBoundingClientRect()).toMatchObject({ left: 16, top: 16 });
    handle.dispatchEvent(new Event('pointerup'));
    panel.querySelector('button[aria-label="Mute microphone"]').click();
    expect(mocks.phone.toggleMute).toHaveBeenCalledOnce();
    expect(panel.getBoundingClientRect()).toMatchObject({ left: 16, top: 16 });
  });

  it('supports keyboard movement and reclamps after a narrow viewport resize', async () => {
    wrapper = mount(AgentWebphone);
    await flushPromises();
    const panel = document.body.querySelector('aside');
    const handle = panel.querySelector('button[aria-label^="Move webphone"]');
    const before = panel.getBoundingClientRect();
    handle.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft' }));
    expect(panel.getBoundingClientRect().left).toBe(before.left - 10);
    vi.stubGlobal('innerWidth', 320);
    vi.stubGlobal('innerHeight', 390);
    window.dispatchEvent(new Event('resize'));
    await flushPromises();
    const rect = panel.getBoundingClientRect();
    expect(rect.left).toBe(16);
    expect(rect.top).toBeGreaterThanOrEqual(16);
    expect(rect.top + rect.height).toBeLessThanOrEqual(374);
  });

  it('uses a full-screen mobile panel and a restore/end bar without desktop positioning', async () => {
    mocks.desktop.value = false;
    wrapper = mount(AgentWebphone);
    await flushPromises();
    const panel = document.body.querySelector('aside');
    expect(panel.classList.contains('inset-0')).toBe(true);
    expect(
      panel.querySelector('button[aria-label^="Move webphone"]')
    ).toBeNull();
    expect(frames.has(panel)).toBe(false);
    panel.querySelector('button[aria-label="Minimize webphone"]').click();
    await flushPromises();
    expect(panel.classList.contains('left-20')).toBe(true);
    expect(panel.classList.contains('z-30')).toBe(true);
    expect(panel.classList.contains('inset-0')).toBe(false);
    panel.querySelector('button[aria-label="Expand webphone"]').click();
    await flushPromises();
    expect(panel.classList.contains('inset-0')).toBe(true);
    expect(mocks.phone.call.remote_address).toBe('1002');
    mocks.phone.expanded = false;
    await flushPromises();
    panel.querySelector('button[aria-label="End call"]').click();
    await flushPromises();
    expect(mocks.phone.hangup).toHaveBeenCalledOnce();
  });

  it('removes desktop drag transforms when switching to mobile', async () => {
    wrapper = mount(AgentWebphone);
    await flushPromises();
    const panel = document.body.querySelector('aside');
    expect(frames.has(panel)).toBe(true);
    mocks.desktop.value = false;
    await flushPromises();
    expect(frames.has(panel)).toBe(false);
    mocks.resize();
    expect(frames.has(panel)).toBe(false);
    mocks.desktop.value = true;
    await flushPromises();
    expect(frames.has(panel)).toBe(true);
  });

  it.each([true, false])(
    'keeps the specific denial visible after answering ends the call (desktop %s)',
    async desktop => {
      mocks.desktop.value = desktop;
      mocks.phone.call = {
        state: 'ringing',
        direction: 'incoming',
        remote_address: '1002',
      };
      mocks.phone.answer = vi.fn(async () => {
        mocks.phone.call = null;
        mocks.phone.error = 'microphone_denied';
        throw new Error('microphone_denied');
      });
      wrapper = mount(AgentWebphone);
      await flushPromises();
      document.body.querySelector('button[aria-label="Answer"]').click();
      await flushPromises();
      const panel = document.body.querySelector('aside');
      expect(mocks.phone.error).toBe('microphone_denied');
      expect(panel.querySelector('[role="alert"]').textContent).toContain(
        'Microphone access denied'
      );
      expect(panel.textContent).toContain('Allow microphone access');
      expect(panel.classList.contains('inset-0')).toBe(false);
      expect(mocks.phone.hangup).not.toHaveBeenCalled();
      panel.querySelector('button[aria-label="Close"]').click();
      await flushPromises();
      expect(document.body.querySelector('aside')).toBeNull();
      expect(mocks.phone.error).toBe('');
    }
  );

  it('still shows a generic error for actions without a specific reported reason', async () => {
    mocks.phone.hangup.mockRejectedValue(new Error('network error'));
    wrapper = mount(AgentWebphone);
    await flushPromises();
    document.body.querySelector('button[aria-label="End call"]').click();
    await flushPromises();
    expect(mocks.phone.error).toBe('action_failed');
    expect(document.body.querySelector('[role="alert"]').textContent).toContain(
      'The action could not be completed'
    );
  });

  it('keeps the panel within the visible viewport above the software keyboard', async () => {
    const viewport = new EventTarget();
    Object.assign(viewport, {
      width: 390,
      height: 180,
      offsetTop: 35,
      offsetLeft: 0,
    });
    vi.stubGlobal('visualViewport', viewport);
    vi.stubGlobal('innerWidth', 390);
    wrapper = mount(AgentWebphone);
    await flushPromises();
    const panel = document.body.querySelector('aside');
    const rect = panel.getBoundingClientRect();
    expect(rect.top).toBeGreaterThanOrEqual(51);
    expect(rect.top + rect.height).toBeLessThanOrEqual(199);
    expect(frames.get(panel).maxHeight).toBe('148px');
  });
});
