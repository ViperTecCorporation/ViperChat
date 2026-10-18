import API from '../whatsappTemplates';

describe('WhatsApp templates API', () => {
  beforeEach(() => {
    vi.stubGlobal('axios', { get: vi.fn(), post: vi.fn() });
    vi.spyOn(API, 'accountIdFromRoute', 'get').mockReturnValue('9');
  });
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it('reads the cached list scoped to account and inbox', () => {
    API.get(3);
    expect(window.axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/9/inboxes/3/whatsapp_templates'
    );
    expect(window.axios.post).not.toHaveBeenCalled();
  });
  it('creates only on explicit invocation, wrapping template', () => {
    const template = {
      name: 'hello',
      body: 'Hi',
      category: 'UTILITY',
      language: 'pt_BR',
    };
    API.create(3, template);
    expect(window.axios.post).toHaveBeenCalledExactlyOnceWith(
      '/api/v1/accounts/9/inboxes/3/whatsapp_templates',
      { template }
    );
  });
  it('uses the synchronous sync endpoint, not the legacy job', () => {
    API.sync(3);
    expect(window.axios.post).toHaveBeenCalledExactlyOnceWith(
      '/api/v1/accounts/9/inboxes/3/whatsapp_templates/sync'
    );
  });
});
