import { shallowMount } from '@vue/test-utils';
import ContactInfo from './ContactInfo.vue';
import AvatarPreview from 'next/avatar/AvatarPreview.vue';

vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: false }),
}));

describe('contact sidebar avatar', () => {
  const mountPanel = (props = {}) =>
    shallowMount(ContactInfo, {
      props: {
        contact: {
          id: 1,
          name: 'Contact',
          thumbnail: '/photo.png',
          additional_attributes: {},
        },
        ...props,
      },
      global: {
        mocks: {
          $route: { params: { accountId: 1 } },
          $store: {
            getters: { 'contacts/getUIFlags': {}, getSelectedChat: {} },
            dispatch: vi.fn(),
          },
        },
      },
    });

  it('uses the shared image modal with the current contact photo', async () => {
    const wrapper = mountPanel();
    expect(wrapper.findComponent(AvatarPreview).props()).toMatchObject({
      src: '/photo.png',
      name: 'Contact',
    });
    await wrapper.setProps({
      contact: { id: 2, name: 'Other', thumbnail: '/other.png' },
    });
    expect(wrapper.findComponent(AvatarPreview).props()).toMatchObject({
      src: '/other.png',
      name: 'Other',
    });
  });

  it('keeps the avatar hidden when requested', () => {
    expect(
      mountPanel({ showAvatar: false }).findComponent(AvatarPreview).exists()
    ).toBe(false);
  });
});
