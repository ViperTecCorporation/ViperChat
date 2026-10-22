import { mount, flushPromises } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import AgentTransferPicker from '../AgentTransferPicker.vue';

const mocks = vi.hoisted(() => ({ directory: vi.fn(), phone: null }));
vi.mock('dashboard/api/voip', () => ({
  VoipAPI: class {
    directory = mocks.directory;
  },
}));
vi.mock('dashboard/stores/agentVoip', () => ({
  useAgentVoipStore: () => mocks.phone,
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: ref(1) }),
}));

describe('transfer extension picker', () => {
  let wrapper;
  beforeEach(() => {
    mocks.phone = reactive({
      activeService: { id: 7 },
      activeBinding: { extension: '1001' },
    });
    mocks.directory.mockResolvedValue({
      data: {
        items: [
          { id: 1, name: 'Own extension', address: '1001' },
          { id: 2, name: 'Other operator', address: '1002', avatar_url: '' },
        ],
        total: 17,
      },
    });
  });
  afterEach(() => wrapper?.unmount());

  it('loads only this service and selects an operator without automatically transferring', async () => {
    wrapper = mount(AgentTransferPicker);
    await flushPromises();
    expect(mocks.directory).toHaveBeenCalledWith({
      service_id: 7,
      kind: 'extensions',
      search: '',
      page: 1,
    });
    expect(wrapper.text()).not.toContain('Own extension');
    await wrapper.get('li button').trigger('click');
    expect(wrapper.get('input[autocomplete="off"]').element.value).toBe('1002');
    expect(wrapper.emitted('transfer')).toBeUndefined();
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('transfer')).toEqual([['1002']]);
  });

  it('supports manual input, search, pagination and disables sending during pending transfer', async () => {
    wrapper = mount(AgentTransferPicker);
    await flushPromises();
    await wrapper.get('button[aria-label="Next page"]').trigger('click');
    await flushPromises();
    expect(mocks.directory).toHaveBeenLastCalledWith(
      expect.objectContaining({ page: 2 })
    );
    await wrapper.get('input[type="search"]').setValue('operator');
    await flushPromises();
    expect(mocks.directory).toHaveBeenLastCalledWith(
      expect.objectContaining({ page: 1, search: 'operator' })
    );
    await wrapper.get('input[autocomplete="off"]').setValue('1003');
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('transfer')).toEqual([['1003']]);
    await wrapper.setProps({ busy: true });
    expect(
      wrapper.get('button[type="submit"]').attributes('disabled')
    ).toBeDefined();
  });

  it('keeps manual transfer available and shows the directory failure', async () => {
    mocks.directory.mockRejectedValueOnce(new Error('offline'));
    wrapper = mount(AgentTransferPicker);
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    await wrapper.get('input[autocomplete="off"]').setValue('1004');
    expect(
      wrapper.get('button[type="submit"]').attributes('disabled')
    ).toBeUndefined();
  });
});
