export const LEGACY_REQUIRED_ATTRIBUTE_SCOPE = 'all';

export const normalizeRequiredAttributeRule = rule => {
  if (typeof rule === 'string') {
    return {
      attributeKey: rule,
      scope: LEGACY_REQUIRED_ATTRIBUTE_SCOPE,
      value: rule,
    };
  }

  if (!rule || typeof rule !== 'object') return null;

  const attributeKey = rule.attribute_key || rule.attributeKey;
  const inboxId = rule.inbox_id || rule.inboxId;
  if (!attributeKey || !inboxId) return null;

  return {
    attributeKey,
    inboxId: Number(inboxId),
    applyToGroups: !!(rule.apply_to_groups || rule.applyToGroups),
    scope: 'inbox',
    value: `${attributeKey}:${Number(inboxId)}`,
  };
};

export const normalizeRequiredAttributeRules = rules =>
  (Array.isArray(rules) ? rules : [])
    .map(normalizeRequiredAttributeRule)
    .filter(Boolean);

export const serializeRequiredAttributeRule = rule => ({
  attribute_key: rule.attributeKey,
  inbox_id: Number(rule.inboxId),
  apply_to_groups: !!rule.applyToGroups,
});

export const isRequiredRuleForConversation = (rule, conversation = {}) => {
  if (rule.scope === LEGACY_REQUIRED_ATTRIBUTE_SCOPE) return true;

  const conversationInboxId = Number(
    conversation.inbox_id || conversation.inboxId
  );
  if (!conversationInboxId || conversationInboxId !== Number(rule.inboxId)) {
    return false;
  }

  if (conversation.group) {
    return !!rule.applyToGroups;
  }

  return true;
};

export const hasRequiredRuleForAttribute = (rules, attributeKey) =>
  normalizeRequiredAttributeRules(rules).some(
    rule => rule.attributeKey === attributeKey
  );
