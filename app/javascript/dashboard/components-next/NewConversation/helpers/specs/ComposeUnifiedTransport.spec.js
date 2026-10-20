import { shallowMount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import ComposeNewConversationForm from '../../components/ComposeNewConversationForm.vue';
import WhatsappTransportSelector from '../../components/WhatsappTransportSelector.vue';
import { inboxes } from './whatsappUnifiedInbox.fixtures';

vi.mock('dashboard/composables/useCopilotReply', () => ({
  useCopilotReply: () => ({ reset: vi.fn() }),
}));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));

describe('new compose transport selection', () => {
  let wrapper;
  let formState;
  beforeEach(() => {
    formState = reactive({
      message: 'keep my draft',
      attachedFiles: [{ blobSignedId: 'signed-blob' }],
      subject: '',
      ccEmails: '',
      bccEmails: '',
    });
    wrapper = shallowMount(ComposeNewConversationForm, {
      props: {
        targetInbox: inboxes[0],
        selectedContact: { id: 3, contactInboxes: inboxes },
        currentUser: { id: 4 },
        formState,
        contactConversationsUiFlags: {},
        contactsUiFlags: {},
      },
    });
  });
  afterEach(() => wrapper.unmount());

  it('defaults to Uno even when Meta owns history, enabling text and media', () => {
    expect(wrapper.findComponent({ name: 'MessageEditor' }).exists()).toBe(
      true
    );
    expect(
      wrapper.findComponent({ name: 'ActionButtons' }).props()
    ).toMatchObject({
      isWhatsappInbox: false,
      isEmailOrWebWidgetInbox: true,
      inboxId: 2,
    });
    expect(wrapper.emitted('createConversation')).toBeUndefined();
  });

  it('uses the selected Meta catalog and physical transport ID, retaining draft and attachments', async () => {
    const selector = wrapper.findComponent(WhatsappTransportSelector);
    selector.vm.$emit('update:modelValue', 'whatsapp_cloud');
    await flushPromises();
    expect(wrapper.findComponent({ name: 'MessageEditor' }).exists()).toBe(
      false
    );
    expect(
      wrapper.findComponent({ name: 'ActionButtons' }).props()
    ).toMatchObject({
      isWhatsappInbox: true,
      inboxId: 1,
      messageTemplates: [{ id: 9 }],
    });
    selector.vm.$emit('update:modelValue', 'unoapi');
    await flushPromises();
    expect(formState.message).toBe('keep my draft');
    expect(formState.attachedFiles).toEqual([{ blobSignedId: 'signed-blob' }]);
    expect(wrapper.emitted('createConversation')).toBeUndefined();
  });

  it('sends an attachments-only Uno draft to the primary with the explicit transport', async () => {
    formState.message = '';
    wrapper.findComponent({ name: 'ActionButtons' }).vm.$emit('sendMessage');
    await flushPromises();
    expect(wrapper.emitted('createConversation')[0][0]).toMatchObject({
      payload: {
        inboxId: 1,
        message: { content: '', whatsapp_transport: 'unoapi' },
        files: ['signed-blob'],
      },
    });
    expect(formState.attachedFiles).toHaveLength(1);
  });

  it('requires either a body or an attachment for Uno', async () => {
    formState.message = '';
    formState.attachedFiles = [];
    await flushPromises();
    wrapper.findComponent({ name: 'ActionButtons' }).vm.$emit('sendMessage');
    await flushPromises();
    expect(wrapper.emitted('createConversation')).toBeUndefined();
  });

  it('sends a Meta template through the primary with Meta explicitly selected', async () => {
    wrapper
      .findComponent(WhatsappTransportSelector)
      .vm.$emit('update:modelValue', 'whatsapp_cloud');
    await flushPromises();
    wrapper
      .findComponent({ name: 'ActionButtons' })
      .vm.$emit('sendWhatsappMessage', {
        message: 'Welcome',
        templateParams: { name: 'welcome' },
      });
    await flushPromises();
    expect(wrapper.emitted('createConversation')[0][0].payload).toMatchObject({
      inboxId: 1,
      message: {
        whatsapp_transport: 'whatsapp_cloud',
        template_params: { name: 'welcome' },
      },
    });
  });

  it('blocks unknown transports including keyboard-triggered events', async () => {
    wrapper
      .findComponent(WhatsappTransportSelector)
      .vm.$emit('update:modelValue', 'unknown');
    await flushPromises();
    expect(
      wrapper
        .findComponent({ name: 'ActionButtons' })
        .props('disableSendButton')
    ).toBe(true);
    wrapper.findComponent({ name: 'ActionButtons' }).vm.$emit('sendMessage');
    await flushPromises();
    expect(wrapper.emitted('createConversation')).toBeUndefined();
  });
});

describe('accessible transport selector', () => {
  it.each([
    null,
    { ...inboxes[0], whatsapp_inbox_link: null },
    {
      ...inboxes[0],
      whatsapp_inbox_link: {
        ...inboxes[0].whatsapp_inbox_link,
        enabled: false,
      },
    },
  ])('hides for missing and disabled links', inbox => {
    const wrapper = shallowMount(WhatsappTransportSelector, {
      props: { inbox },
    });
    expect(wrapper.find('select').exists()).toBe(false);
    wrapper.unmount();
  });
  it('hides for groups even with active link metadata', () => {
    const wrapper = shallowMount(WhatsappTransportSelector, {
      props: { inbox: inboxes[0], contact: { groupSourceId: '123@g.us' } },
    });
    expect(wrapper.find('select').exists()).toBe(false);
    wrapper.unmount();
  });
});
