import { shallowMount } from '@vue/test-utils';
import ScheduledMessageCard from './ScheduledMessageCard.vue';

const item = {
  id: 1,
  contact: { name: 'Contact' },
  inbox: { name: 'Inbox' },
  label: { title: 'Follow up' },
  sender: { name: 'Agent' },
  status: 'scheduled',
};

describe('scheduled transport provenance', () => {
  it('does not add transport metadata to unlinked cards', () => {
    const wrapper = shallowMount(ScheduledMessageCard, { props: { item } });
    expect(
      wrapper.find('[data-testid="scheduled-transport-provenance"]').exists()
    ).toBe(false);
  });

  it('shows the original provider for an inferred legacy schedule and per-item capability routing', () => {
    const wrapper = shallowMount(ScheduledMessageCard, {
      props: {
        item: {
          ...item,
          whatsapp_transport: {
            requested_provider: 'whatsapp_cloud',
            selection_source: 'legacy_inbox',
            pending_capture: true,
          },
          messages: [
            {
              content: 'Text',
              whatsapp_transport: { provider: 'whatsapp_cloud' },
            },
            {
              content: 'Contacts',
              whatsapp_transport: {
                provider: 'unoapi',
                reason: 'capability_routing',
              },
            },
          ],
        },
      },
    });
    expect(wrapper.text()).toContain('Scheduled via: Meta');
    expect(wrapper.text()).toContain('original inbox provider');
    expect(wrapper.text()).toContain('Message 1 · Effective provider: Meta');
    expect(wrapper.text()).toContain(
      'Message 2 · Effective provider: ViperConnect'
    );
    expect(wrapper.text()).toContain('routed by supported feature');
    expect(
      wrapper.get('[data-testid="scheduled-transport-provenance"]').classes()
    ).toContain('break-words');
  });
});
