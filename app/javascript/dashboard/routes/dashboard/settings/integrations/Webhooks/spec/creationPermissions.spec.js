import Webhooks from '../Index.vue';

describe('webhook creation permissions', () => {
  it.each([true, false])('respects the flag on self-hosted: %s', enabled => {
    const context = {
      isOnChatwootCloud: false,
      accountId: 1,
      isFeatureEnabledonAccount: () => enabled,
    };
    context.apiAndWebhooksEnabled =
      Webhooks.computed.apiAndWebhooksEnabled.call(context);
    expect(context.apiAndWebhooksEnabled).toBe(true);
    expect(Webhooks.computed.canCreateWebhook.call(context)).toBe(enabled);
  });

  it('does not open creation but allows editing existing webhooks', () => {
    const context = { canCreateWebhook: false, showAddPopup: false };
    Webhooks.methods.openAddPopup.call(context);
    expect(context.showAddPopup).toBe(false);
    const webhook = { id: 7, url: 'https://example.com' };
    Webhooks.methods.openEditPopup.call(context, webhook);
    expect(context.showEditPopup).toBe(true);
    expect(context.selectedWebHook).toBe(webhook);
  });
});
