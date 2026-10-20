import { shallowMount, flushPromises } from '@vue/test-utils';
import { computed } from 'vue';
import ForwardMessagesModal from 'dashboard/components/widgets/conversation/ForwardMessagesModal.vue';
import ConversationApi from 'dashboard/api/conversations';
import SearchAPI from 'dashboard/api/search';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import {
  fetchContactableInboxes,
  searchContacts,
} from '../composeConversationHelper';
import { inboxes } from './whatsappUnifiedInbox.fixtures';

vi.mock('dashboard/composables/store', () => ({ useMapGetter: vi.fn() }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/conversations', () => ({
  default: { forwardMessages: vi.fn() },
}));
vi.mock('dashboard/api/search', () => ({
  default: { conversations: vi.fn() },
}));
vi.mock('../composeConversationHelper', async importOriginal => ({
  ...(await importOriginal()),
  fetchContactableInboxes: vi.fn(),
  searchContacts: vi.fn(),
}));

describe('forward transport routing', () => {
  let wrapper;
  beforeEach(() => {
    useMapGetter.mockImplementation(key =>
      computed(() => (key === 'getCurrentUser' ? { id: 4 } : inboxes))
    );
    fetchContactableInboxes.mockResolvedValue(inboxes);
    wrapper = shallowMount(ForwardMessagesModal, {
      props: {
        show: true,
        conversationId: 12,
        selectedMessages: [{ id: 5, content: 'Forward draft' }],
      },
      global: { stubs: { Modal: { template: '<div><slot /></div>' } } },
    });
  });
  afterEach(() => wrapper.unmount());

  it('sends the unified primary and root transport and prevents concurrent clicks', async () => {
    wrapper
      .findComponent({ name: 'ContactSelector' })
      .vm.$emit('setSelectedContact', { action: 'contact', id: 3 });
    await flushPromises();
    const selector = wrapper.findComponent({ name: 'InboxSelector' });
    expect(selector.props('contactableInboxesList')).toHaveLength(1);
    selector.vm.$emit(
      'handleInboxAction',
      selector.props('contactableInboxesList')[0]
    );
    await flushPromises();
    let resolve;
    ConversationApi.forwardMessages.mockReturnValue(
      new Promise(done => {
        resolve = done;
      })
    );
    const send = wrapper.findAllComponents({ name: 'Button' }).at(-1);
    send.vm.$emit('click');
    send.vm.$emit('click');
    await flushPromises();
    expect(ConversationApi.forwardMessages).toHaveBeenCalledTimes(1);
    expect(ConversationApi.forwardMessages).toHaveBeenCalledWith(12, {
      message_ids: [5],
      target_contact_id: 3,
      target_inbox_id: 1,
      whatsapp_transport: 'unoapi',
    });
    resolve({ data: {} });
    await flushPromises();
    expect(wrapper.emitted('forwarded')).toHaveLength(1);
  });

  it('shows the actual Meta API error and keeps the selection and preview', async () => {
    wrapper
      .findComponent({ name: 'ContactSelector' })
      .vm.$emit('setSelectedContact', { action: 'contact', id: 3 });
    await flushPromises();
    wrapper
      .findComponent({ name: 'InboxSelector' })
      .vm.$emit('handleInboxAction', inboxes[1]);
    await flushPromises();
    wrapper
      .findComponent({ name: 'WhatsappTransportSelector' })
      .vm.$emit('update:modelValue', 'whatsapp_cloud');
    await flushPromises();
    ConversationApi.forwardMessages.mockRejectedValue({
      response: { data: { error: 'Meta messaging window is closed' } },
    });
    wrapper.findAllComponents({ name: 'Button' }).at(-1).vm.$emit('click');
    await flushPromises();
    expect(useAlert).toHaveBeenCalledWith('Meta messaging window is closed');
    expect(wrapper.props('show')).toBe(true);
    expect(wrapper.text()).toContain('Forward draft');
    expect(
      wrapper.findComponent({ name: 'InboxSelector' }).props('targetInbox').id
    ).toBe(2);
    expect(
      wrapper
        .findComponent({ name: 'WhatsappTransportSelector' })
        .props('modelValue')
    ).toBe('whatsapp_cloud');
    expect(wrapper.emitted('forwarded')).toBeUndefined();
    expect(
      ConversationApi.forwardMessages.mock.calls[0][1].whatsapp_transport
    ).toBe('whatsapp_cloud');
  });

  it('forwards to an existing group using its actual physical inbox without transport', async () => {
    searchContacts.mockResolvedValue([]);
    SearchAPI.conversations.mockResolvedValue({
      data: {
        payload: {
          conversations: [
            { id: 30, group: true, group_source_id: '123@g.us', inbox_id: 2 },
          ],
        },
      },
    });
    wrapper
      .findComponent({ name: 'ContactSelector' })
      .vm.$emit('searchContacts', 'Group');
    await flushPromises();
    const contactSelector = wrapper.findComponent({ name: 'ContactSelector' });
    const group = contactSelector.props('contacts')[0];
    contactSelector.vm.$emit('setSelectedContact', {
      action: 'contact',
      ...group,
    });
    await flushPromises();
    expect(
      wrapper.findComponent({ name: 'WhatsappTransportSelector' }).exists()
    ).toBe(false);
    expect(contactSelector.props('selectedContact')).toMatchObject({
      groupSourceId: '123@g.us',
      contactInboxes: [{ id: 2 }],
    });
    ConversationApi.forwardMessages.mockResolvedValue({ data: {} });
    wrapper.findAllComponents({ name: 'Button' }).at(-1).vm.$emit('click');
    await flushPromises();
    expect(ConversationApi.forwardMessages).toHaveBeenCalledWith(12, {
      message_ids: [5],
      target_conversation_id: 30,
    });
  });
});
