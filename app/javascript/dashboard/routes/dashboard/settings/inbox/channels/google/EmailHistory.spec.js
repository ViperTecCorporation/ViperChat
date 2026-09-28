import { mount, flushPromises } from '@vue/test-utils';
import EmailHistory from './EmailHistory.vue';
import googleClient from 'dashboard/api/channel/googleClient';

vi.mock('dashboard/api/channel/googleClient', () => ({
  default: { getHistory: vi.fn(), startHistory: vi.fn(), stopHistory: vi.fn() },
}));
describe('Gmail history settings', () => {
  it('loads progress, starts the selected period and stops without deleting mail', async () => {
    googleClient.getHistory.mockResolvedValue({
      data: { status: 'not_started' },
    });
    googleClient.startHistory.mockResolvedValue({
      data: { status: 'running', processed: 50, day: '2026-09-25' },
    });
    googleClient.stopHistory.mockResolvedValue({ data: { status: 'stopped' } });
    const wrapper = mount(EmailHistory, {
      props: { inboxId: 61 },
      global: {
        mocks: { $t: key => key },
        stubs: {
          NextButton: {
            props: ['label', 'disabled'],
            template: '<button :disabled="disabled">{{ label }}</button>',
          },
        },
      },
    });
    await flushPromises();
    expect(googleClient.getHistory).toHaveBeenCalledWith(61);
    await wrapper.find('select').setValue('6m');
    await wrapper
      .findAll('button')
      .find(button => button.text().endsWith('START'))
      .trigger('click');
    await flushPromises();
    expect(googleClient.startHistory).toHaveBeenCalledWith(61, '6m');
    await wrapper
      .findAll('button')
      .find(button => button.text().endsWith('STOP'))
      .trigger('click');
    await flushPromises();
    expect(googleClient.stopHistory).toHaveBeenCalledWith(61);
    wrapper.unmount();
  });
});
