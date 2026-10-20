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
const existingLink = {
  id: 4,
  primary_inbox_id: 2,
  secondary_inbox_id: 1,
  default_provider: 'unoapi',
  enabled: true,
};

describe('unified inbox channel preferences', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    Inboxes.getWhatsappLink.mockResolvedValue(response);
  });

  it.each([true, false])(
    'persists policy=%s from general Update and reloads it despite historical conflicts',
    async enabled => {
      let stored = {
        ...existingLink,
        activated_at: '2026-10-17T12:00:00Z',
        meta_initial_messages_enabled: !enabled,
        meta_initial_messages_limit: 5,
      };
      Inboxes.getWhatsappLink.mockImplementation(async () => ({
        data: { ...response.data, link: { ...stored } },
      }));
      Inboxes.updateWhatsappLink.mockImplementation(async (_id, payload) => {
        stored = { ...stored, ...payload };
        return { data: { ...response.data, link: { ...stored } } };
      });
      Inboxes.previewWhatsappLink.mockResolvedValue({
        data: { preview: { conflicts: ['historical conflict'] } },
      });
      const options = { props: { inbox: { id: 1 } }, global };
      let wrapper = mount(WhatsappUnifiedInbox, options);
      await flushPromises();
      await wrapper.findAll('button')[0].trigger('click');
      await flushPromises();
      await wrapper.findAll('input[type=checkbox]')[1].setValue(enabled);
      await wrapper.find('input[type=number]').setValue(10);
      expect(wrapper.findAll('button')[1].element.disabled).toBe(false);
      await wrapper.vm.savePendingChanges();
      expect(Inboxes.updateWhatsappLink).toHaveBeenCalledWith(
        1,
        expect.objectContaining({
          meta_initial_messages_enabled: enabled,
          meta_initial_messages_limit: 10,
          default_provider: 'unoapi',
          enabled: true,
        })
      );
      expect(wrapper.text()).toContain('WHATSAPP_UNIFIED.SAVED');
      await wrapper.vm.savePendingChanges();
      expect(Inboxes.updateWhatsappLink).toHaveBeenCalledOnce();
      wrapper.unmount();
      wrapper = mount(WhatsappUnifiedInbox, options);
      await flushPromises();
      expect(wrapper.findAll('input[type=checkbox]')[1].element.checked).toBe(
        enabled
      );
      expect(wrapper.find('input[type=number]').element.value).toBe('10');
      wrapper.unmount();
    }
  );

  it('saves an active policy directly with Save link, without a new preview', async () => {
    const stored = { ...existingLink, activated_at: '2026-10-17' };
    Inboxes.getWhatsappLink.mockResolvedValue({
      data: { ...response.data, link: stored },
    });
    Inboxes.updateWhatsappLink.mockResolvedValue({
      data: {
        ...response.data,
        link: {
          ...stored,
          meta_initial_messages_enabled: true,
          meta_initial_messages_limit: 5,
        },
      },
    });
    const wrapper = mount(WhatsappUnifiedInbox, {
      props: { inbox: { id: 1 } },
      global,
    });
    await flushPromises();
    await wrapper.findAll('input[type=checkbox]')[1].setValue(true);
    await wrapper.findAll('button')[1].trigger('click');
    await flushPromises();
    expect(Inboxes.previewWhatsappLink).not.toHaveBeenCalled();
    expect(Inboxes.updateWhatsappLink).toHaveBeenCalledOnce();
    expect(wrapper.text()).toContain('WHATSAPP_UNIFIED.SAVED');
    wrapper.unmount();
  });

  it('propagates failed persistence and preserves edits for another attempt', async () => {
    Inboxes.getWhatsappLink.mockResolvedValue({
      data: {
        ...response.data,
        link: { ...existingLink, activated_at: '2026-10-17' },
      },
    });
    Inboxes.updateWhatsappLink.mockRejectedValue(new Error('Network failure'));
    const wrapper = mount(WhatsappUnifiedInbox, {
      props: { inbox: { id: 1 } },
      global,
    });
    await flushPromises();
    await wrapper.findAll('input[type=checkbox]')[1].setValue(true);
    await expect(wrapper.vm.savePendingChanges()).rejects.toThrow(
      'Network failure'
    );
    expect(wrapper.find('[role=alert]').text()).toBe('Network failure');
    expect(wrapper.text()).not.toContain('WHATSAPP_UNIFIED.SAVED');
    expect(wrapper.findAll('input[type=checkbox]')[1].element.checked).toBe(
      true
    );
    wrapper.unmount();
  });

  it('does not activate an unreviewed link through the general Update button', async () => {
    Inboxes.getWhatsappLink.mockResolvedValue({
      data: { ...response.data, link: { ...existingLink, enabled: false } },
    });
    const wrapper = mount(WhatsappUnifiedInbox, {
      props: { inbox: { id: 1 } },
      global,
    });
    await flushPromises();
    await wrapper.findAll('input[type=checkbox]')[0].setValue(true);
    await expect(wrapper.vm.savePendingChanges()).rejects.toMatchObject({
      code: 'whatsapp_link_review_required',
    });
    expect(Inboxes.updateWhatsappLink).not.toHaveBeenCalled();
    wrapper.unmount();
  });

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
      meta_initial_messages_enabled: false,
      meta_initial_messages_limit: 5,
    });
    const confirm = wrapper.findAll('input[type=checkbox]')[2];
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
    await wrapper.findAll('input[type=checkbox]')[2].setValue(true);
    expect(wrapper.text()).toContain('active conversations');
    expect(wrapper.findAll('button')[1].element.disabled).toBe(true);
    wrapper.unmount();
  });

  it.each([null, existingLink])(
    'defaults the initial Meta policy to false/5 when fields are missing: %s',
    async link => {
      Inboxes.getWhatsappLink.mockResolvedValue({
        data: { ...response.data, link },
      });
      const wrapper = mount(WhatsappUnifiedInbox, {
        props: { inbox: { id: 1, name: 'ViperConnect' } },
        global,
      });
      await flushPromises();
      expect(wrapper.findAll('input[type=checkbox]')[1].element.checked).toBe(
        false
      );
      const limit = wrapper.find('input[type=number]');
      expect(limit.element.value).toBe('5');
      expect(limit.attributes()).toMatchObject({
        min: '0',
        max: '1000',
        step: '1',
        'aria-invalid': 'false',
      });
      expect(limit.classes()).toEqual(
        expect.arrayContaining(['w-full', 'min-w-0'])
      );
      expect(wrapper.text()).toContain(
        'WHATSAPP_UNIFIED.META_INITIAL_MESSAGES.HELP'
      );
      wrapper.unmount();
    }
  );

  it.each([0, 5, 1000])(
    'loads and submits policy limit %s without changing the default provider',
    async limit => {
      const link = {
        ...existingLink,
        meta_initial_messages_enabled: true,
        meta_initial_messages_limit: limit,
      };
      Inboxes.getWhatsappLink.mockResolvedValue({
        data: { ...response.data, link },
      });
      Inboxes.previewWhatsappLink.mockResolvedValue({
        data: { preview: { conflicts: [], confirmation: 'policy-token' } },
      });
      Inboxes.updateWhatsappLink.mockResolvedValue({
        data: {
          ...response.data,
          link: {
            ...link,
            meta_initial_messages_enabled: false,
            meta_initial_messages_limit: 0,
          },
        },
      });
      const wrapper = mount(WhatsappUnifiedInbox, {
        props: { inbox: { id: 1, name: 'ViperConnect' } },
        global,
      });
      await flushPromises();
      expect(wrapper.find('input[type=number]').element.value).toBe(
        String(limit)
      );
      expect(wrapper.findAll('input[type=checkbox]')[1].element.checked).toBe(
        true
      );
      await wrapper.findAll('button')[0].trigger('click');
      await flushPromises();
      const policyPayload = expect.objectContaining({
        default_provider: 'unoapi',
        meta_initial_messages_enabled: true,
        meta_initial_messages_limit: limit,
      });
      expect(Inboxes.previewWhatsappLink).toHaveBeenCalledWith(
        1,
        policyPayload
      );
      await wrapper.findAll('input[type=checkbox]')[2].setValue(true);
      await wrapper.findAll('button')[1].trigger('click');
      await flushPromises();
      expect(Inboxes.updateWhatsappLink).toHaveBeenCalledWith(1, policyPayload);
      expect(wrapper.findAll('input[type=checkbox]')[1].element.checked).toBe(
        false
      );
      expect(wrapper.find('input[type=number]').element.value).toBe('0');
      expect(wrapper.findAll('select')[2].element.value).toBe('unoapi');
      wrapper.unmount();
    }
  );

  it.each(['enabled', 'limit', '', '-1', '1.5', '1001', 'invalid'])(
    'invalidates preview and confirmation after policy edit: %s',
    async edit => {
      Inboxes.getWhatsappLink.mockResolvedValue({
        data: { ...response.data, link: existingLink },
      });
      Inboxes.previewWhatsappLink.mockResolvedValue({
        data: { preview: { conflicts: [], confirmation: 'policy-token' } },
      });
      const wrapper = mount(WhatsappUnifiedInbox, {
        props: { inbox: { id: 1, name: 'ViperConnect' } },
        global,
      });
      await flushPromises();
      await wrapper.findAll('button')[0].trigger('click');
      await flushPromises();
      const confirm = wrapper.findAll('input[type=checkbox]')[2];
      await confirm.setValue(true);
      expect(wrapper.findAll('button')[1].element.disabled).toBe(false);
      if (edit === 'enabled') {
        await wrapper.findAll('input[type=checkbox]')[1].setValue(true);
      } else {
        await wrapper
          .find('input[type=number]')
          .setValue(edit === 'limit' ? '6' : edit);
      }
      expect(confirm.element.checked).toBe(false);
      expect(wrapper.text()).not.toContain('WHATSAPP_UNIFIED.NO_CONFLICTS');
      expect(wrapper.findAll('button')[1].element.disabled).toBe(true);
      expect(wrapper.findAll('select')[2].element.value).toBe('unoapi');
      const invalid = !['enabled', 'limit'].includes(edit);
      expect(wrapper.findAll('button')[0].element.disabled).toBe(invalid);
      expect(
        wrapper.find('input[type=number]').attributes('aria-invalid')
      ).toBe(String(invalid));
      if (invalid) {
        await wrapper.findAll('button')[0].trigger('click');
        await confirm.setValue(true);
        await wrapper.findAll('button')[1].trigger('click');
        expect(Inboxes.previewWhatsappLink).toHaveBeenCalledOnce();
        expect(Inboxes.updateWhatsappLink).not.toHaveBeenCalled();
        expect(wrapper.find('[role=alert]').text()).toBe(
          'WHATSAPP_UNIFIED.META_INITIAL_MESSAGES.LIMIT_HELP'
        );
      }
      wrapper.unmount();
    }
  );
});
