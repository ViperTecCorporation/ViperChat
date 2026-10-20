import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import { createI18n } from 'vue-i18n';
import { useAdmin } from 'dashboard/composables/useAdmin';
import API from 'dashboard/api/whatsappTemplates';
import en from 'dashboard/i18n/locale/en/whatsappTemplates.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/whatsappTemplates.json';
import WhatsappTemplates from '../WhatsappTemplates.vue';

vi.mock('dashboard/composables/useAdmin', () => ({ useAdmin: vi.fn() }));
vi.mock('dashboard/api/whatsappTemplates', () => ({
  default: { get: vi.fn(), create: vi.fn(), sync: vi.fn() },
}));

describe('WhatsApp template management', () => {
  let wrapper;
  let isAdmin;
  const template = {
    id: 'meta1',
    name: 'order_update',
    category: 'UTILITY',
    language: 'pt_BR',
    status: 'PENDING',
    components: [{ type: 'BODY', text: 'Hello {{1}}' }],
  };
  beforeEach(() => {
    isAdmin = ref(true);
    useAdmin.mockReturnValue({ isAdmin });
    API.get.mockResolvedValue({
      data: { templates: [], last_updated_at: null },
    });
    API.sync.mockResolvedValue({
      data: { templates: [template], last_updated_at: '2026-10-17T12:00:00Z' },
    });
    API.create.mockResolvedValue({ data: { template } });
  });
  afterEach(() => wrapper?.unmount());

  it('only loads cache on entry; never posts on draft changes; escapes preview', async () => {
    wrapper = mount(WhatsappTemplates, {
      props: { inboxId: 3 },
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'en', messages: { en } }),
        ],
      },
    });
    await flushPromises();
    expect(API.get).toHaveBeenCalledExactlyOnceWith(3);
    await wrapper.get('[data-test="name"]').setValue('order_update');
    await wrapper.get('[data-test="body"]').setValue('Hello {{1}}');
    await wrapper
      .get('[data-test="example-1"]')
      .setValue('<img src=x onerror=alert(1)>');
    expect(wrapper.get('[data-test="preview"]').text()).toContain('<img');
    expect(wrapper.get('[data-test="preview"]').find('img').exists()).toBe(
      false
    );
    expect(API.create).not.toHaveBeenCalled();
    expect(API.sync).not.toHaveBeenCalled();
  });

  it('submits once, locks during creation and displays actual PENDING status', async () => {
    let resolve;
    API.create.mockReturnValue(
      new Promise(done => {
        resolve = done;
      })
    );
    wrapper = mount(WhatsappTemplates, {
      props: { inboxId: 3 },
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'en', messages: { en } }),
        ],
      },
    });
    await flushPromises();
    await wrapper.get('[data-test="name"]').setValue('order_update');
    await wrapper.get('[data-test="body"]').setValue('Hello {{1}}');
    await wrapper.get('[data-test="example-1"]').setValue('Ada');
    await wrapper.get('form').trigger('submit');
    expect(wrapper.get('fieldset').element.disabled).toBe(true);
    await wrapper.get('form').trigger('submit');
    expect(API.create).toHaveBeenCalledTimes(1);
    expect(API.create).toHaveBeenCalledWith(
      3,
      expect.objectContaining({ examples: ['Ada'], body: 'Hello {{1}}' })
    );
    resolve({ data: { template } });
    await flushPromises();
    expect(wrapper.text()).toContain('PENDING');
    expect(wrapper.text()).not.toContain('APPROVED');
  });

  it.each([
    'permission_denied',
    'authentication_required',
    'validation_failed',
    'provider_rejected',
    'temporarily_unavailable',
    'configuration_missing',
    'name_conflict',
    'unsupported_provider',
  ])('preserves draft on %s and escapes provider message', async code => {
    API.create.mockRejectedValue({
      response: {
        data: {
          error: code,
          provider_message: '<script>reason</script>',
          provider_code: 100,
          provider_subcode: 12,
        },
      },
    });
    wrapper = mount(WhatsappTemplates, {
      props: { inboxId: 3 },
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'pt_BR',
            messages: { pt_BR: ptBR },
          }),
        ],
      },
    });
    await flushPromises();
    await wrapper.get('[data-test="name"]').setValue('order_update');
    await wrapper.get('[data-test="body"]').setValue('Hello');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[data-test="name"]').element.value).toBe(
      'order_update'
    );
    expect(wrapper.get('[data-test="body"]').element.value).toBe('Hello');
    expect(wrapper.get('[role="alert"]').text()).toBe(
      ptBR.WHATSAPP_TEMPLATE_CREATION.ERRORS[code]
    );
    expect(wrapper.get('[data-test="provider-message"]').text()).toBe(
      '<script>reason</script> — Código retornado pela Meta: 100'
    );
    expect(wrapper.find('script').exists()).toBe(false);
    expect(wrapper.get('fieldset').element.disabled).toBe(false);
    expect(API.create).toHaveBeenCalledTimes(1);
  });

  it('blocks uncertain retries until explicit sync finds matching identity and content', async () => {
    API.create.mockRejectedValue(new Error('network'));
    wrapper = mount(WhatsappTemplates, {
      props: { inboxId: 3 },
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'en', messages: { en } }),
        ],
      },
    });
    await flushPromises();
    await wrapper.get('[data-test="name"]').setValue('order_update');
    await wrapper.get('[data-test="body"]').setValue('Hello {{1}}');
    await wrapper.get('[data-test="example-1"]').setValue('Ada');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.text()).toContain(en.WHATSAPP_TEMPLATE_CREATION.UNCERTAIN);
    await wrapper.get('form').trigger('submit');
    expect(API.create).toHaveBeenCalledTimes(1);
    API.sync.mockResolvedValueOnce({
      data: {
        templates: [
          { ...template, components: [{ type: 'BODY', text: 'Different' }] },
        ],
        last_updated_at: null,
      },
    });
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain(en.WHATSAPP_TEMPLATE_CREATION.UNCERTAIN);
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(API.sync).toHaveBeenCalledTimes(2);
    expect(wrapper.text()).not.toContain(
      en.WHATSAPP_TEMPLATE_CREATION.UNCERTAIN
    );
    expect(wrapper.text()).toContain('PENDING');
    expect(API.create).toHaveBeenCalledTimes(1);
  });

  it('shows synchronous sync permission failure immediately and preserves named cache entries', async () => {
    API.get.mockResolvedValue({
      data: {
        templates: [
          { ...template, name: 'named_cached', parameter_format: 'NAMED' },
        ],
        last_updated_at: null,
      },
    });
    API.sync.mockRejectedValue({
      response: { data: { error: 'permission_denied' } },
    });
    wrapper = mount(WhatsappTemplates, {
      props: { inboxId: 3 },
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'en', messages: { en } }),
        ],
      },
    });
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('named_cached');
    expect(wrapper.get('[role="alert"]').text()).toBe(
      en.WHATSAPP_TEMPLATE_CREATION.ERRORS.permission_denied
    );
  });

  it('does not load hidden tab or nonadmin content', async () => {
    wrapper = mount(WhatsappTemplates, {
      props: { inboxId: 3, active: false },
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'en', messages: { en } }),
        ],
      },
    });
    await flushPromises();
    expect(API.get).not.toHaveBeenCalled();
    isAdmin.value = false;
    await wrapper.setProps({ active: true });
    expect(wrapper.find('form').exists()).toBe(false);
    expect(API.get).not.toHaveBeenCalled();
  });
});
