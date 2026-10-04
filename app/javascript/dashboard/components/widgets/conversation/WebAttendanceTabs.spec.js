import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { ref } from 'vue';
import { describe, expect, it, vi } from 'vitest';
import MessagesView from './MessagesView.vue';

vi.mock('dashboard/composables/useLabelSuggestions', () => ({
  useLabelSuggestions: () => ({
    captainTasksEnabled: ref(false),
    isLabelSuggestionFeatureEnabled: ref(false),
    getLabelSuggestions: vi.fn(),
  }),
}));
vi.mock('dashboard/composables/useWebAttendance', () => ({
  useWebAttendance: () => ({
    attendance: ref({
      enabled: true,
      active: true,
      can_invite: false,
      unread: { channel: 0, web: 0 },
    }),
    refresh: vi.fn().mockResolvedValue({ unread: { channel: 0, web: 0 } }),
    seen: vi.fn().mockResolvedValue(),
  }),
}));

const ReplyStub = {
  props: [
    'deliveryDestination',
    'initialReplyMode',
    'isComposerActive',
    'managedDestinations',
    'webAttendanceActive',
    'popOutReplyBox',
  ],
  emits: ['setReplyMode', 'toggleEditorSize', 'update:popOutReplyBox'],
  data: () => ({ draft: '' }),
  // A fragment deliberately matches ReplyBox's multiple roots.
  template: `<span />
    <section :data-composer="initialReplyMode === 'NOTE' ? 'note' : deliveryDestination">
      <input v-model="draft" />
      <button @click="$emit('setReplyMode', initialReplyMode === 'NOTE' ? 'REPLY' : 'NOTE')" />
    </section>`,
};

describe('web attendance mounted composers', () => {
  it.each(['unoapi', 'whatsapp_cloud'])(
    'keeps %s Web outside the WhatsApp window and preserves all drafts',
    async provider => {
      const store = createStore({
        getters: {
          getSelectedChat: () => ({
            id: 42,
            inbox_id: 7,
            can_reply: false,
            messages: [],
            status: 'open',
          }),
          getCurrentUserID: () => 1,
          getCurrentAccountId: () => 1,
          getAllMessagesLoaded: () => true,
          'inboxes/getInbox': () => () => ({
            channel_type: 'Channel::Whatsapp',
            provider,
            web_attendance_enabled: true,
          }),
          'globalConfig/get': () => ({}),
          'inboxes/getInstagramInboxByInstagramId': () => () => null,
          'globalConfig/isOnChatwootCloud': () => false,
          'conversationTypingStatus/getUserList': () => () => [],
        },
        actions: { fetchAllAttachments: vi.fn() },
      });
      const wrapper = mount(MessagesView, {
        global: {
          plugins: [store],
          mocks: { $t: key => key, $route: { query: {} } },
          stubs: {
            ReplyBox: ReplyStub,
            ResizableEditorWrapper: { template: '<div><slot /></div>' },
            MessageList: { template: '<div class="conversation-panel" />' },
            Banner: true,
          },
        },
      });
      await flushPromises();
      const channel = wrapper.find('[data-composer="channel"]');
      const web = wrapper.find('[data-composer="web"]');
      const note = wrapper.find('[data-composer="note"]');
      expect(channel.element.parentElement.style.display).not.toBe('none');
      expect(web.element.parentElement.style.display).toBe('none');
      expect(note.element.parentElement.style.display).toBe('none');
      await channel.find('input').setValue('WhatsApp draft');
      await wrapper.findAll('[role="tab"]')[1].trigger('click');
      expect(wrapper.vm.deliveryDestination).toBe('web');
      expect(channel.element.parentElement.style.display).toBe('none');
      expect(web.element.parentElement.style.display).not.toBe('none');
      await web.find('input').setValue('Web draft');
      await web.find('button').trigger('click');
      expect(note.element.parentElement.style.display).not.toBe('none');
      expect(web.element.parentElement.style.display).toBe('none');
      await note.find('input').setValue('Common note');
      await wrapper.findAll('[role="tab"]')[0].trigger('click');
      expect(note.element.parentElement.style.display).not.toBe('none');
      expect(note.find('input').element.value).toBe('Common note');
      await note.find('button').trigger('click');
      expect(channel.find('input').element.value).toBe('WhatsApp draft');
      await wrapper.findAll('[role="tab"]')[1].trigger('click');
      expect(web.find('input').element.value).toBe('Web draft');
      wrapper.unmount();
    }
  );
});
