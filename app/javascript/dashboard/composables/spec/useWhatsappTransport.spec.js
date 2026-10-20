import { computed, ref } from 'vue';
import { mount } from '@vue/test-utils';
import {
  useWhatsappTransport,
  withWhatsappTransport,
  resolveWhatsappTransport,
} from '../useWhatsappTransport';
import WhatsappTransportSelector from 'dashboard/components/widgets/WootWriter/WhatsappTransportSelector.vue';
import { createPendingMessage } from 'dashboard/helper/commons';
import { buildCreatePayload } from 'dashboard/api/inbox/message';

describe('shared WhatsApp transport preference', () => {
  it.each(['unoapi', 'whatsapp_cloud'])(
    'persists compact/full remounts with %s as default',
    async defaultProvider => {
      const chat = ref({
        id: defaultProvider,
        account_id: 13,
        whatsapp_transport_options: {
          link_id: 5,
          default_provider: defaultProvider,
          transports: [
            {
              provider: 'unoapi',
              label: 'ViperConnect',
              inbox_id: 1,
              can_reply: true,
            },
            {
              provider: 'whatsapp_cloud',
              label: 'Meta',
              inbox_id: 2,
              can_reply: true,
            },
          ],
        },
      });
      const preference = useWhatsappTransport(chat, 7);
      const Editor = {
        components: { WhatsappTransportSelector },
        setup: () => ({
          provider: preference.selectedProvider,
          transports: computed(
            () => chat.value.whatsapp_transport_options.transports
          ),
        }),
        template:
          '<WhatsappTransportSelector v-model="provider" :transports="transports" />',
      };
      const alternate =
        defaultProvider === 'unoapi' ? 'whatsapp_cloud' : 'unoapi';
      const compact = mount(Editor, { global: { mocks: { $t: key => key } } });
      await compact.get('select').setValue(alternate);
      compact.unmount();
      const full = mount(Editor, { global: { mocks: { $t: key => key } } });
      expect(full.get('select').element.value).toBe(alternate);
      chat.value = { ...chat.value, can_reply: false };
      expect(preference.selectedProvider.value).toBe(alternate);
      await full.get('select').setValue(defaultProvider);
      full.unmount();
      const compactAgain = mount(Editor, {
        global: { mocks: { $t: key => key } },
      });
      expect(compactAgain.get('select').element.value).toBe(defaultProvider);
      compactAgain.unmount();
    }
  );

  it('isolates account, user, conversation and link changes without silently replacing unavailable selections', () => {
    const chat = ref({
      id: 451,
      account_id: 5,
      whatsapp_transport_options: {
        link_id: 2,
        default_provider: 'unoapi',
        transports: [],
      },
    });
    const preference = useWhatsappTransport(chat, 1);
    preference.selectedProvider.value = 'whatsapp_cloud';
    expect(useWhatsappTransport(chat, 2).selectedProvider.value).toBe('unoapi');
    expect(preference.selectedTransport.value).toBeUndefined();
    expect(preference.selectedProvider.value).toBe('whatsapp_cloud');
    chat.value = { ...chat.value, account_id: 9 };
    expect(preference.selectedProvider.value).toBe('unoapi');
    chat.value = { ...chat.value, account_id: 5, id: 452 };
    expect(preference.selectedProvider.value).toBe('unoapi');
    chat.value = { ...chat.value, id: 451 };
    expect(preference.selectedProvider.value).toBe('whatsapp_cloud');
  });
});

describe('declared capability preflight', () => {
  it.each(['unoapi', 'whatsapp_cloud'])(
    'routes a known incompatibility from %s without changing preference',
    provider => {
      const alternate = provider === 'unoapi' ? 'whatsapp_cloud' : 'unoapi';
      const options = {
        transports: [
          {
            provider,
            can_reply: true,
            capabilities: { text: true, quote: false },
          },
          {
            provider: alternate,
            can_reply: true,
            capabilities: { text: true, quote: true },
          },
        ],
      };
      expect(
        resolveWhatsappTransport(options, provider, ['text', 'quote'])
      ).toEqual({
        transport: options.transports[1],
        reason: 'capability_routing',
      });
      expect(options.transports[0].provider).toBe(provider);
    }
  );

  it('does not infer support, route around closed windows or route to unavailable partners', () => {
    const options = {
      transports: [
        {
          provider: 'unoapi',
          can_reply: false,
          capabilities: { text: true, view_once: false },
        },
        {
          provider: 'whatsapp_cloud',
          can_reply: true,
          capabilities: { text: true },
        },
      ],
    };
    expect(resolveWhatsappTransport(options, 'unoapi', ['text']).reason).toBe(
      'unavailable'
    );
    expect(
      resolveWhatsappTransport(options, 'whatsapp_cloud', ['view_once']).reason
    ).toBe('unknown');
    expect(
      resolveWhatsappTransport(options, 'unoapi', ['view_once']).reason
    ).toBe('unsupported');
  });
});

describe('outgoing transport boundary', () => {
  it.each([undefined, ['signed-blob']])(
    'preserves explicit transport through pending messages and JSON/FormData (%s)',
    files => {
      const pending = createPendingMessage(
        withWhatsappTransport(
          { conversationId: 1, message: 'hello', files, private: false },
          'whatsapp_cloud'
        )
      );
      expect(pending.whatsapp_transport).toBe('whatsapp_cloud');
      const payload = buildCreatePayload({
        message: pending.message,
        files: pending.files,
        whatsappTransport: pending.whatsapp_transport,
        isPrivate: false,
      });
      expect(
        files ? payload.get('whatsapp_transport') : payload.whatsapp_transport
      ).toBe('whatsapp_cloud');
    }
  );

  it.each([
    [false, 'web'],
    [true, 'channel'],
    [true, 'web'],
  ])(
    'never leaks transport into private=%s destination=%s',
    (isPrivate, destination) => {
      const message = withWhatsappTransport(
        { private: isPrivate, whatsapp_transport: 'unoapi' },
        'whatsapp_cloud',
        destination
      );
      expect(message).not.toHaveProperty('whatsapp_transport');
      [undefined, ['blob']].forEach(files => {
        const payload = buildCreatePayload({
          isPrivate,
          files,
          deliveryDestination: destination,
          whatsappTransport: 'whatsapp_cloud',
        });
        expect(
          files
            ? payload.has('whatsapp_transport')
            : 'whatsapp_transport' in payload
        ).toBe(false);
      });
    }
  );
});
