import { mount } from '@vue/test-utils';
import TimeAgo from '../TimeAgo.vue';

describe('TimeAgo', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-10-12T12:00:00Z'));
  });

  afterEach(() => vi.useRealTimers());

  const createWrapper = (props = {}, locale = 'pt_BR') =>
    mount(TimeAgo, {
      props: {
        createdAtTimestamp: Date.parse('2025-09-29T12:00:00Z') / 1000,
        lastActivityTimestamp: Date.parse('2026-10-10T12:00:00Z') / 1000,
        isAutoRefreshEnabled: false,
        ...props,
      },
      global: {
        mocks: {
          $i18n: { locale },
          $t: key =>
            key.includes('CREATED') ? 'Criado em:' : 'Última atividade',
        },
      },
    });

  it('uses Portuguese relative time and Brazilian dates', () => {
    const wrapper = createWrapper();
    expect(wrapper.text()).toBe('1a • 2d');
    expect(wrapper.vm.tooltipText).toBe(
      'Criado em: 29/09/2025 • Última atividade há 2 dias'
    );
  });

  it('hides creation in both the row and tooltip', async () => {
    const wrapper = createWrapper({ showCreatedAt: false });
    expect(wrapper.text()).toBe('2d');
    expect(wrapper.vm.tooltipText).toBe('Última atividade há 2 dias');
    await wrapper.setProps({ showCreatedAt: true });
    expect(wrapper.text()).toBe('1a • 2d');
  });

  it('shows agora for recent activity', () => {
    const wrapper = createWrapper({
      showCreatedAt: false,
      lastActivityTimestamp: Date.now() / 1000,
    });
    expect(wrapper.text()).toBe('agora');
    expect(wrapper.vm.tooltipText).toBe('Última atividade agora');
  });

  it('preserves English formatting', () => {
    const wrapper = createWrapper({}, 'en');
    expect(wrapper.text()).toBe('1y • 2d');
    expect(wrapper.vm.tooltipText).toContain('Sep 29, 2025');
    expect(wrapper.vm.tooltipText).toContain('2 days ago');
  });

  it('localizes compact month units', () => {
    const wrapper = createWrapper();
    expect(wrapper.vm.compactTime('about a month ago')).toBe('1mês');
    expect(wrapper.vm.compactTime('2 months ago')).toBe('2meses');
  });
});
