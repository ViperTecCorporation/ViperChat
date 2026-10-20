import { computed, reactive, toValue } from 'vue';

// Session scoped and shared by compact/full editors, never inferred from inbox order.
const preferences = reactive(new Map());

export function useWhatsappTransport(conversation, userId) {
  const options = computed(
    () => toValue(conversation)?.whatsapp_transport_options
  );
  const key = computed(() => {
    const chat = toValue(conversation);
    return `${toValue(userId)}:${chat?.account_id}:${chat?.id}:${options.value?.link_id}`;
  });
  const selectedProvider = computed({
    get: () => preferences.get(key.value) || options.value?.default_provider,
    set: provider => preferences.set(key.value, provider),
  });
  const selectedTransport = computed(() =>
    options.value?.transports?.find(
      transport => transport.provider === selectedProvider.value
    )
  );
  return { options, selectedProvider, selectedTransport };
}

export function withWhatsappTransport(
  payload,
  provider,
  destination = 'channel'
) {
  const { whatsapp_transport: ignored, ...message } = payload;
  return {
    ...message,
    delivery_destination: message.private ? 'channel' : destination,
    ...(!message.private && destination !== 'web' && provider
      ? { whatsapp_transport: provider }
      : {}),
  };
}

export function resolveWhatsappTransport(options, provider, capabilities) {
  const selected = options?.transports.find(item => item.provider === provider);
  const supports = transport =>
    capabilities.every(
      capability => transport?.capabilities?.[capability] === true
    );
  if (supports(selected)) {
    return {
      transport: selected,
      reason: selected.can_reply ? 'selected' : 'unavailable',
    };
  }
  // Unknown support, closed windows and failures never authorize trying the partner.
  if (
    !capabilities.some(
      capability => selected?.capabilities?.[capability] === false
    )
  ) {
    return { reason: 'unknown' };
  }
  const alternate = options.transports.find(
    item => item.provider !== provider && item.can_reply && supports(item)
  );
  return alternate
    ? { transport: alternate, reason: 'capability_routing' }
    : { reason: 'unsupported' };
}
