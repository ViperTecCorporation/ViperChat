import { mount, flushPromises } from '@vue/test-utils';
import WhatsappUnifiedInbox from '../WhatsappUnifiedInbox.vue';
import Inboxes from 'dashboard/api/inboxes';

vi.mock('dashboard/api/inboxes', () => ({
  default: {
    getWhatsappLink: vi.fn(),
    previewWhatsappLink: vi.fn(),
    updateWhatsappLink: vi.fn(),
    deleteWhatsappLink: vi.fn(),
  },
}));

const response = {
  data: {
    link: null,
    candidates: [
      {
        id: 2,
        name: 'Meta with a very long inbox name',
        provider: 'whatsapp_cloud',
      },
    ],
  },
};
const global = {
  mocks: { $t: key => key },
  stubs: { WhatsappUnifiedReviews: true },
};

describe('unified inbox channel preferences', () => {
  beforeEach(() => Inboxes.getWhatsappLink.mockResolvedValue(response));

  it('explains an empty compatible-inbox list and disables the empty dropdown', async () => {
    Inboxes.getWhatsappLink.mockResolvedValue({
      data: { link: null, candidates: [] },
    });
    const wrapper = mount(WhatsappUnifiedInbox, {
      props: { inbox: { id: 1, name: 'ViperConnect' } },
      global,
    });
    await flushPromises();
    const partner = wrapper.find('select');
    expect(partner.element.disabled).toBe(true);
    expect(partner.text()).toContain('WHATSAPP_UNIFIED.NO_CANDIDATES');
    expect(partner.attributes('aria-describedby')).toBe(
      'whatsapp-partner-empty-1'
    );
    expect(wrapper.find('#whatsapp-partner-empty-1').attributes('role')).toBe(
      'status'
    );
    expect(wrapper.find('#whatsapp-partner-empty-1').text()).toBe(
      'WHATSAPP_UNIFIED.NO_CANDIDATES_HELP'
    );
    wrapper.unmount();
  });

  it('does not display an empty-state warning when a partner is available', async () => {
    const wrapper = mount(WhatsappUnifiedInbox, {
      props: { inbox: { id: 1, name: 'ViperConnect' } },
      global,
    });
    await flushPromises();
    expect(wrapper.find('select').element.disabled).toBe(false);
    expect(wrapper.find('#whatsapp-partner-empty-1').exists()).toBe(false);
    wrapper.unmount();
  });

  it.each([true, false])(
    'shows administrative review for an existing link, enabled=%s',
    async enabled => {
      Inboxes.getWhatsappLink.mockResolvedValue({
        data: {
          ...response.data,
          link: {
            id: 4,
            primary_inbox_id: 2,
            secondary_inbox_id: 1,
            enabled,
            default_provider: 'unoapi',
          },
        },
      });
      const wrapper = mount(WhatsappUnifiedInbox, {
        props: { inbox: { id: 1, name: 'ViperConnect' } },
        global,
      });
      await flushPromises();
      const reviews = wrapper.findComponent({ name: 'WhatsappUnifiedReviews' });
      expect(reviews.exists()).toBe(true);
      expect(reviews.props()).toMatchObject({
        inboxId: 1,
        linkEnabled: enabled,
      });
      wrapper.unmount();
    }
  );

  it('does not offer a review panel before a link exists', async () => {
    const wrapper = mount(WhatsappUnifiedInbox, {
      props: { inbox: { id: 1, name: 'ViperConnect' } },
      global,
    });
    await flushPromises();
    expect(
      wrapper.findComponent({ name: 'WhatsappUnifiedReviews' }).exists()
    ).toBe(false);
    wrapper.unmount();
  });

  it.each([320, 360, 390, 412, 430, 1280])(
    'uses stacked, bounded configuration controls at width %s',
    async width => {
      window.innerWidth = width;
      const wrapper = mount(WhatsappUnifiedInbox, {
        props: { inbox: { id: 1, name: 'ViperConnect', provider: 'unoapi' } },
        global,
      });
      await flushPromises();
      expect(wrapper.classes()).toContain('min-w-0');
      expect(wrapper.findAll('select')).toHaveLength(3);
      wrapper
        .findAll('select')
        .forEach(select => expect(select.classes()).toContain('min-w-0'));
      expect(wrapper.find('input[type=checkbox]').element.checked).toBe(false);
      const buttons = wrapper.findAll('button');
      expect(buttons[0].element.disabled).toBe(true);
      expect(buttons[1].element.disabled).toBe(true);
      expect(wrapper.find('.sm\\:flex-row').exists()).toBe(true);
      wrapper.unmount();
    }
  );

  it('requires preview and confirmation, invalidates preview after edits, and keeps primary independent of default', async () => {
    Inboxes.previewWhatsappLink.mockResolvedValue({
      data: {
        preview: { conflicts: [], confirmation: 'signed-preview-token' },
      },
    });
    Inboxes.updateWhatsappLink.mockResolvedValue(response);
    const wrapper = mount(WhatsappUnifiedInbox, {
      props: { inbox: { id: 1, name: 'ViperConnect' } },
      global,
    });
    await flushPromises();
    const selects = wrapper.findAll('select');
    await wrapper.findAll('input[type=checkbox]')[0].setValue(true);
    await selects[0].setValue('2');
    await selects[1].setValue('2');
    await selects[2].setValue('unoapi');
    await wrapper.findAll('button')[0].trigger('click');
    await flushPromises();
    expect(Inboxes.previewWhatsappLink).toHaveBeenCalledWith(1, {
      partner_inbox_id: 2,
      primary_inbox_id: 2,
      default_provider: 'unoapi',
      enabled: true,
    });
    const confirm = wrapper.findAll('input[type=checkbox]')[1];
    expect(wrapper.findAll('button')[1].element.disabled).toBe(true);
    await confirm.setValue(true);
    expect(wrapper.findAll('button')[1].element.disabled).toBe(false);
    await selects[2].setValue('whatsapp_cloud');
    expect(wrapper.findAll('button')[1].element.disabled).toBe(true);
    expect(confirm.element.checked).toBe(false);
    await wrapper.findAll('button')[0].trigger('click');
    await flushPromises();
    await confirm.setValue(true);
    await wrapper.findAll('button')[1].trigger('click');
    await flushPromises();
    expect(Inboxes.updateWhatsappLink).toHaveBeenCalledOnce();
    expect(Inboxes.updateWhatsappLink).toHaveBeenCalledWith(
      1,
      expect.objectContaining({
        confirmation: 'signed-preview-token',
        default_provider: 'whatsapp_cloud',
        primary_inbox_id: 2,
      })
    );
    wrapper.unmount();
  });

  it('surfaces conflicts and prevents save, preserves the activated primary', async () => {
    Inboxes.getWhatsappLink.mockResolvedValue({
      data: {
        ...response.data,
        link: {
          id: 4,
          primary_inbox_id: 2,
          secondary_inbox_id: 1,
          default_provider: 'unoapi',
          enabled: true,
          activated_at: '2026-10-16',
        },
      },
    });
    Inboxes.previewWhatsappLink.mockResolvedValue({
      data: { preview: { conflicts: ['active conversations'] } },
    });
    const wrapper = mount(WhatsappUnifiedInbox, {
      props: { inbox: { id: 1, name: 'ViperConnect' } },
      global,
    });
    await flushPromises();
    expect(wrapper.findAll('select')[0].element.disabled).toBe(true);
    expect(wrapper.findAll('select')[1].element.disabled).toBe(true);
    await wrapper.findAll('button')[0].trigger('click');
    await flushPromises();
    await wrapper.findAll('input[type=checkbox]')[1].setValue(true);
    expect(wrapper.text()).toContain('active conversations');
    expect(wrapper.findAll('button')[1].element.disabled).toBe(true);
    wrapper.unmount();
  });
});
