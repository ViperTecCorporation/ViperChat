import inboxesAPI from '../inboxes';
import ApiClient from '../ApiClient';

describe('#InboxesAPI', () => {
  it('creates correct instance', () => {
    expect(inboxesAPI).toBeInstanceOf(ApiClient);
    expect(inboxesAPI).toHaveProperty('get');
    expect(inboxesAPI).toHaveProperty('show');
    expect(inboxesAPI).toHaveProperty('create');
    expect(inboxesAPI).toHaveProperty('update');
    expect(inboxesAPI).toHaveProperty('delete');
    expect(inboxesAPI).toHaveProperty('getCampaigns');
    expect(inboxesAPI).toHaveProperty('getAgentBot');
    expect(inboxesAPI).toHaveProperty('setAgentBot');
    expect(inboxesAPI).toHaveProperty('syncTemplates');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve()),
      get: vi.fn(() => Promise.resolve()),
      patch: vi.fn(() => Promise.resolve()),
      delete: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('#getCampaigns', () => {
      inboxesAPI.getCampaigns(2);
      expect(axiosMock.get).toHaveBeenCalledWith('/api/v1/inboxes/2/campaigns');
    });

    it('#deleteInboxAvatar', () => {
      inboxesAPI.deleteInboxAvatar(2);
      expect(axiosMock.delete).toHaveBeenCalledWith('/api/v1/inboxes/2/avatar');
    });

    it('#syncTemplates', () => {
      inboxesAPI.syncTemplates(2);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/inboxes/2/sync_templates'
      );
    });

    it('#getWhatsappLinkReviews scopes filters and pagination to the inbox', () => {
      const params = { page: 2, kind: 'event', status: 'open' };
      inboxesAPI.getWhatsappLinkReviews(2, params);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/inboxes/2/whatsapp_link/reviews',
        { params }
      );
    });

    it('#recheckWhatsappLinkReview passes only the version and encodes the id', () => {
      inboxesAPI.recheckWhatsappLinkReview(2, 'event-123/extra', 'v1');
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/inboxes/2/whatsapp_link/reviews/event-123%2Fextra/recheck',
        { version: 'v1' }
      );
    });

    it('#acknowledgeWhatsappLinkReview never passes sending state or payload', () => {
      inboxesAPI.acknowledgeWhatsappLinkReview(2, 'delivery-123', 'v2');
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/inboxes/2/whatsapp_link/reviews/delivery-123/acknowledge',
        { version: 'v2' }
      );
    });
  });
});
