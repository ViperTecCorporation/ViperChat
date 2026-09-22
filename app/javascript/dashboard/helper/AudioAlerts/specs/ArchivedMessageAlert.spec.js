import { DashboardAudioNotificationHelper } from '../DashboardAudioNotificationHelper';
vi.mock('dashboard/store', () => ({ default: { getters: {} } }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

it('does not play a realtime message alert for an archived conversation', () => {
  const helper = new DashboardAudioNotificationHelper({
    getters: {
      getCurrentAccountId: 1,
      getUISettings: { archived_conversations: { 1: [7] } },
    },
  });
  const play = vi.spyOn(helper, 'playAudioAlert');
  helper.onNewMessage({ conversation_id: 7, message_type: 0 });
  expect(play).not.toHaveBeenCalled();
});
