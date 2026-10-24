export const CACHE_DB = 'viper-frontend-cache-v1';
export const CACHE_TTL = 24 * 60 * 60 * 1000;
export const MAX_CACHE_BYTES = 5 * 1024 * 1024;
export const CACHE_EPOCH_KEY = 'viper-frontend-cache-epoch';

export const cacheEpoch = () => {
  try {
    return localStorage.getItem(CACHE_EPOCH_KEY) || '0';
  } catch {
    return '0';
  }
};

const pick = (value, keys) =>
  Object.fromEntries(
    keys.filter(key => value?.[key] !== undefined).map(key => [key, value[key]])
  );
const person = value =>
  value
    ? pick(value, [
        'id',
        'name',
        'available_name',
        'phone_number',
        'email',
        'thumbnail',
        'avatar_url',
        'type',
        'availability_status',
      ])
    : null;
const blockedKey =
  /token|password|secret|credential|api_key|authorization|pubsub|signed_id|(^|_)(url|data_url|thumb_url)$/i;
const plainData = value => {
  if (Array.isArray(value)) return value.map(plainData);
  if (value && typeof value === 'object')
    return Object.fromEntries(
      Object.entries(value)
        .filter(([key]) => !blockedKey.test(key))
        .map(([key, data]) => [key, plainData(data)])
    );
  return typeof value === 'string' ? value.slice(0, 20000) : value;
};
export const cacheScope = (user, accountId) => {
  const membership = user?.accounts?.find(
    account => Number(account.id) === Number(accountId)
  );
  if (!user?.id || !membership || membership.status === 'suspended')
    return null;
  const origin = new URL(
    window.chatwootConfig?.apiHost || window.location.origin
  ).origin;
  const installation = window.viperNativeInstallation?.installationId || origin;
  return {
    accountId: Number(accountId),
    userId: user.id,
    key: JSON.stringify([
      origin,
      installation,
      user.id,
      Number(accountId),
      cacheEpoch(),
    ]),
    permissions: JSON.stringify([
      membership.role,
      membership.custom_role_id,
      [...(membership.permissions || [])].sort(),
      membership.status,
    ]),
  };
};

export const buildSnapshot = (state, scope, savedAt) => {
  const conversations = state.conversations.allConversations
    .filter(chat => Number(chat.account_id) === scope.accountId)
    .slice()
    .sort(
      (a, b) =>
        Number(b.id === state.conversations.selectedChatId) -
          Number(a.id === state.conversations.selectedChatId) ||
        Number(b.last_activity_at || 0) - Number(a.last_activity_at || 0)
    )
    .slice(0, 100)
    .map(chat => ({
      ...pick(chat, [
        'id',
        'account_id',
        'inbox_id',
        'offline_outbox_version',
        'status',
        'priority',
        'unread_count',
        'created_at',
        'timestamp',
        'last_activity_at',
        'updated_at',
        'agent_last_seen_at',
        'assignee_last_seen_at',
        'labels',
        'additional_attributes',
      ]),
      meta: {
        ...pick(chat.meta, ['channel', 'assignee_type']),
        sender: person(chat.meta?.sender),
        assignee: person(chat.meta?.assignee),
        team: chat.meta?.team ? pick(chat.meta.team, ['id', 'name']) : null,
      },
      messages: [
        ...new Map(
          (chat.messages || [])
            .filter(
              message =>
                Number.isInteger(message.id) && message.status !== 'in_progress'
            )
            .map(message => [message.id, message])
        ).values(),
      ]
        .slice(-50)
        .map(message => ({
          ...pick(message, [
            'id',
            'conversation_id',
            'account_id',
            'inbox_id',
            'content',
            'processed_message_content',
            'message_type',
            'status',
            'source_id',
            'created_at',
            'private',
            'content_type',
            'content_attributes',
          ]),
          sender: person(message.sender),
          attachments: [],
        })),
    }));
  const snapshot = plainData({
    version: 1,
    scope: scope.key,
    permissions: scope.permissions,
    savedAt,
    lastConversationId: conversations.some(
      chat => chat.id === state.conversations.selectedChatId
    )
      ? state.conversations.selectedChatId
      : null,
    conversations,
    account: pick(
      state.accounts.records.find(
        account => Number(account.id) === scope.accountId
      ),
      ['id', 'name', 'locale', 'features', 'status']
    ),
    inboxes: state.inboxes.records.map(inbox =>
      pick(inbox, [
        'id',
        'name',
        'channel_type',
        'phone_number',
        'avatar_url',
        'provider',
        'enabled',
        'allow_messages_after_resolved',
        'lock_to_single_conversation',
      ])
    ),
    agents: state.agents.records.slice(0, 500).map(person),
    labels: state.labels.records.map(label =>
      pick(label, ['id', 'title', 'color', 'description'])
    ),
    teams: Object.values(state.teams.records).map(team =>
      pick(team, ['id', 'name', 'description', 'is_member'])
    ),
  });
  let bytes = new Blob([JSON.stringify(snapshot)]).size;
  while (snapshot.conversations.length && bytes > MAX_CACHE_BYTES) {
    snapshot.conversations = snapshot.conversations.slice(
      0,
      Math.floor(
        ((snapshot.conversations.length * MAX_CACHE_BYTES) / bytes) * 0.8
      )
    );
    bytes = new Blob([JSON.stringify(snapshot)]).size;
  }
  if (bytes > MAX_CACHE_BYTES) return null;
  return snapshot;
};

export const restoreSnapshot = (state, snapshot) => {
  state.conversations.allConversations = snapshot.conversations.map(chat => ({
    ...chat,
    isCachedSnapshot: true,
    hasCachedMessages: true,
    dataFetched: true,
    allMessagesLoaded: false,
    can_reply: false,
  }));
  state.conversations.listLoadingStatus = false;
  ['inboxes', 'agents', 'labels'].forEach(name => {
    state[name].records = snapshot[name] || [];
  });
  state.teams.records = Object.fromEntries(
    (snapshot.teams || []).map(team => [team.id, team])
  );
  if (snapshot.account?.id) state.accounts.records = [snapshot.account];
  snapshot.conversations.forEach(chat => {
    if (chat.meta?.sender?.id)
      state.contacts.records[chat.meta.sender.id] = chat.meta.sender;
  });
};

export const clearSnapshotView = state => {
  state.conversations.allConversations = [];
  state.conversations.selectedChatId = null;
  state.conversations.attachments = {};
  state.conversations.attachmentsMeta = {};
  ['inboxes', 'agents', 'labels', 'accounts'].forEach(name => {
    state[name].records = [];
  });
  state.teams.records = {};
  state.contacts.records = {};
};
