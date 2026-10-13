import { mount } from '@vue/test-utils';
import { ref, nextTick } from 'vue';
import ContactsDetailsLayout from './ContactsDetailsLayout.vue';

const state = vi.hoisted(() => ({ desktop: null }));
vi.mock('@vueuse/core', async importOriginal => ({
  ...(await importOriginal()),
  useMediaQuery: () => state.desktop,
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { contactId: '1' } }),
}));

describe('ContactsDetailsLayout responsive panel', () => {
  beforeEach(() => {
    state.desktop = ref(false);
  });
  const render = () =>
    mount(ContactsDetailsLayout, {
      props: { selectedContact: { name: 'Contact with a long name' } },
      slots: {
        default: '<div data-testid="details">Details</div>',
        sidebarHeader: '<nav>Tabs</nav>',
        sidebar: '<div data-testid="history">History</div>',
      },
      global: {
        stubs: {
          Button: {
            props: ['label'],
            template: '<button>{{ label }}</button>',
          },
          Breadcrumb: true,
          ComposeConversation: true,
          VoiceCallButton: true,
        },
      },
    });

  it('opens a full-width panel and returns without losing contact details', async () => {
    const wrapper = render();
    expect(wrapper.find('[data-testid="history"]').exists()).toBe(false);
    await wrapper.get('[data-contact-sidebar-toggle]').trigger('click');
    expect(wrapper.get('#contact-sidebar-content').classes()).toContain(
      'w-full'
    );
    expect(wrapper.get('[data-testid="details"]').isVisible()).toBe(false);
    expect(wrapper.findAll('[data-testid="history"]')).toHaveLength(1);
    await wrapper.get('#contact-sidebar-content button').trigger('click');
    expect(wrapper.find('#contact-sidebar-content').exists()).toBe(false);
    expect(wrapper.get('section > div').element.style.display).not.toBe('none');
  });

  it('keeps only one sidebar mounted when resizing to desktop', async () => {
    const wrapper = render();
    await wrapper.get('[data-contact-sidebar-toggle]').trigger('click');
    state.desktop.value = true;
    await nextTick();
    expect(wrapper.find('#contact-sidebar-content').exists()).toBe(false);
    expect(wrapper.findAll('[data-testid="history"]')).toHaveLength(1);
    expect(wrapper.get('[data-testid="details"]').isVisible()).toBe(true);
  });
});
