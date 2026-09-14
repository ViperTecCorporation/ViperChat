import { shallowMount } from '@vue/test-utils';
import NavigationShortcuts from './NavigationShortcuts.vue';

const mocks = vi.hoisted(() => ({ save: vi.fn() }));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: { value: {} },
    updateUISettings: mocks.save,
  }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

describe('profile navigation shortcuts', () => {
  let wrapper;
  beforeEach(() => {
    mocks.save.mockReset().mockResolvedValue({});
    wrapper = shallowMount(NavigationShortcuts, {
      global: {
        stubs: { SectionLayout: { template: '<section><slot /></section>' } },
      },
    });
  });
  it('captures and persists custom combinations', async () => {
    await wrapper
      .findAll('input')[0]
      .trigger('keydown', { key: 'q', ctrlKey: true });
    await wrapper.findAllComponents({ name: 'Button' })[0].vm.$emit('click');
    expect(mocks.save).toHaveBeenCalledWith({
      navigation_shortcuts: expect.objectContaining({
        all: 'Ctrl+Q',
        me: 'Alt+M',
      }),
    });
  });
  it('rejects duplicate combinations without replacing the previous value', async () => {
    await wrapper
      .findAll('input')[0]
      .trigger('keydown', { key: 'm', altKey: true });
    expect(wrapper.findAll('input')[0].element.value).toBe('Alt+T');
    expect(wrapper.text()).toContain('DUPLICATE');
  });
  it('restores the defaults before saving', async () => {
    await wrapper
      .findAll('input')[0]
      .trigger('keydown', { key: 'q', ctrlKey: true });
    await wrapper.findAllComponents({ name: 'Button' })[1].vm.$emit('click');
    expect(wrapper.findAll('input')[0].element.value).toBe('Alt+T');
    expect(mocks.save).not.toHaveBeenCalled();
  });
  it('reports a persistence failure', async () => {
    mocks.save.mockResolvedValue(false);
    await wrapper.vm.save();
    expect(wrapper.text()).toContain('ERROR');
  });
});
