import camelcaseKeys from 'camelcase-keys';

export const isGroupDestination = (contact, inbox) =>
  Boolean(
    contact?.groupSourceId ||
      contact?.group_source_id ||
      [
        contact?.email,
        contact?.sourceId,
        contact?.source_id,
        inbox?.sourceId,
        inbox?.source_id,
      ].some(value => value?.endsWith('@g.us'))
  );

// Metadata is permission-filtered by the server. Never infer a link from phones.
export const getWhatsappInboxLink = (inbox, contact) => {
  if (isGroupDestination(contact, inbox)) return null;
  const normalized = camelcaseKeys(inbox || {}, { deep: true });
  const link = normalized.whatsappInboxLink;
  return link && link.enabled !== false ? link : null;
};

export const collapseWhatsappInboxes = (inboxes, contact) => {
  const normalized = camelcaseKeys(inboxes || [], { deep: true });
  const links = normalized
    .map(inbox => getWhatsappInboxLink(inbox, contact))
    .filter(Boolean);
  const seen = new Set();
  return normalized.reduce((result, inbox) => {
    if (isGroupDestination(contact, inbox)) return [...result, inbox];
    const link = links.find(item =>
      [item.primaryInboxId, item.secondaryInboxId].some(
        id => String(id) === String(inbox.id)
      )
    );
    if (!link) return [...result, inbox];
    const key = String(link.primaryInboxId);
    if (seen.has(key)) return result;
    seen.add(key);
    const primary = normalized.find(item => String(item.id) === key);
    result.push({
      ...inbox,
      ...primary,
      id: link.primaryInboxId,
      name: link.primaryInboxName,
      whatsappInboxLink: link,
    });
    return result;
  }, []);
};

export const getWhatsappTransport = (inbox, provider, contact) => {
  const link = getWhatsappInboxLink(inbox, contact);
  return link?.transports?.find(
    transport =>
      ['unoapi', 'whatsapp_cloud'].includes(transport.provider) &&
      transport.provider === provider
  );
};

export const getWhatsappRouting = (inbox, provider, contact) => {
  const link = getWhatsappInboxLink(inbox, contact);
  if (!link) return { inboxId: inbox.id };
  const selected = provider ?? link.defaultProvider;
  if (!getWhatsappTransport(inbox, selected, contact)) {
    throw new Error('WHATSAPP_UNIFIED.CAPABILITY_UNAVAILABLE');
  }
  return { inboxId: link.primaryInboxId, whatsappTransport: selected };
};
