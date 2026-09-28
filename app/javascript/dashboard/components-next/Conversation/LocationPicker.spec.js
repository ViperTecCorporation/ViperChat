import { mount, flushPromises } from '@vue/test-utils';
import LocationPicker from './LocationPicker.vue';
import { currentLocation } from 'dashboard/helper/locationSharing';

vi.mock('dashboard/helper/locationSharing', () => ({
  currentLocation: vi.fn(),
  locationMessagePayload: vi.fn(),
}));
vi.mock('vuex', () => ({ useStore: () => ({ dispatch: vi.fn() }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

describe('location picker', () => {
  let wrapper;
  const message = data => {
    window.dispatchEvent(
      new MessageEvent('message', {
        origin: window.location.origin,
        source: wrapper.find('iframe').element.contentWindow,
        data: { source: 'viper-location-map', ...data },
      })
    );
  };
  beforeEach(() => {
    vi.clearAllMocks();
    wrapper = mount(LocationPicker, {
      props: { conversationId: 1 },
      global: {
        stubs: {
          teleport: true,
          Modal: { template: '<div><slot /></div>' },
          Button: {
            props: ['label', 'disabled'],
            template: '<button :disabled="disabled">{{ label }}</button>',
          },
        },
      },
    });
  });
  afterEach(() => wrapper.unmount());
  it('requests GPS once when the map is ready, without sending a message', async () => {
    currentLocation.mockResolvedValue({
      coords: { latitude: -11, longitude: -54, accuracy: 8 },
    });
    message({ type: 'ready' });
    await flushPromises();
    message({ type: 'ready' });
    await flushPromises();
    expect(currentLocation).toHaveBeenCalledTimes(1);
    expect(wrapper.text()).toContain('-11.000000');
    expect(wrapper.findAll('input[type="text"]')).toHaveLength(2);
  });
  it('keeps address search available after GPS denial', async () => {
    currentLocation.mockRejectedValue(new Error('denied'));
    message({ type: 'ready' });
    await flushPromises();
    expect(wrapper.find('[role="alert"]').text()).toContain('GPS_ERROR');
    expect(
      wrapper.find('input[type="search"]').attributes('disabled')
    ).toBeUndefined();
  });
  it('fills the business name and address and ignores a late GPS result', async () => {
    let finish;
    currentLocation.mockReturnValue(
      new Promise(resolve => {
        finish = resolve;
      })
    );
    message({ type: 'ready' });
    message({
      type: 'point',
      point: { latitude: -12, longitude: -55 },
      name: 'Viper Tec',
      address: 'Rua Teste',
    });
    finish({ coords: { latitude: -11, longitude: -54, accuracy: 8 } });
    await flushPromises();
    expect(
      wrapper.findAll('input[type="text"]').map(input => input.element.value)
    ).toEqual(['Viper Tec', 'Rua Teste']);
    expect(wrapper.text()).toContain('-12.000000');
  });
});
