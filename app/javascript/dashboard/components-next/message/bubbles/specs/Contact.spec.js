import { flushPromises, mount } from '@vue/test-utils';
import { defineComponent, h, ref } from 'vue';
import ContactBubble from '../Contact.vue';
import { provideMessageContext } from '../../provider.js';

const mocks = vi.hoisted(() => ({
  alert: vi.fn(),
  dispatch: vi.fn(),
  routerPush: vi.fn(),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: mocks.alert,
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref([]),
  useStore: () => ({ dispatch: mocks.dispatch }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
  useRouter: () => ({ push: mocks.routerPush }),
}));

const mountContactBubble = () => {
  const Wrapper = defineComponent({
    setup() {
      provideMessageContext({
        attachments: ref([
          {
            fallbackTitle: '+55 (11) 99999-9999',
            meta: { formattedName: 'Contato existente' },
          },
        ]),
        content: ref(''),
      });

      return () => h(ContactBubble);
    },
  });

  return mount(Wrapper, {
    global: {
      stubs: {
        BaseAttachmentBubble: {
          props: ['action'],
          template:
            '<button type="button" @click="action.onClick">save</button>',
        },
      },
    },
  });
};

describe('ContactBubble', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.routerPush.mockResolvedValue();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('warns and navigates to the existing contact instead of reporting a save failure', async () => {
    mocks.dispatch.mockResolvedValueOnce([{ id: 42 }]);
    const wrapper = mountContactBubble();

    await wrapper.get('button').trigger('click');
    await flushPromises();

    expect(mocks.dispatch).toHaveBeenCalledWith('contacts/filter', {
      queryPayload: {
        payload: [
          expect.objectContaining({
            attribute_key: 'phone_number',
            values: ['5511999999999'],
          }),
        ],
      },
      resetState: false,
    });
    expect(mocks.dispatch).toHaveBeenCalledTimes(1);
    expect(mocks.alert).toHaveBeenCalledWith(
      'CONTACT_FORM.FORM.PHONE_NUMBER.DUPLICATE'
    );
    expect(mocks.routerPush).toHaveBeenCalledWith({
      name: 'contacts_edit',
      params: { accountId: '1', contactId: 42 },
    });
  });
});
