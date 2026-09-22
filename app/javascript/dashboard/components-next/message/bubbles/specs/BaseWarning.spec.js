import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import Base from '../Base.vue';

const context = {};
vi.mock('../../provider.js', () => ({ useMessageContext: () => context }));

describe('Quote not sent notice', () => {
  beforeEach(() => {
    Object.assign(context, {
      id: ref(9),
      conversationId: ref(1),
      variant: ref('agent'),
      orientation: ref('right'),
      inReplyTo: ref({ id: 3, content: 'Original reference' }),
      shouldGroupWithNext: ref(false),
      contentAttributes: ref({}),
    });
  });

  const render = () =>
    mount(Base, {
      global: {
        stubs: { MessageMeta: true, FavoriteIndicator: true },
        directives: { dompurifyHtml: () => {} },
      },
      slots: { default: 'Sent content' },
    });

  it('marks the internal quote without removing sent content or delivery metadata', () => {
    context.contentAttributes.value = {
      unoapiWarnings: [{ code: 'REPLY_SENT_WITHOUT_QUOTE' }],
    };
    const wrapper = render();
    expect(wrapper.text()).toContain('Reference not sent');
    expect(wrapper.text()).toContain('Sent content');
    expect(wrapper.findComponent({ name: 'MessageMeta' }).exists()).toBe(true);
    expect(context.inReplyTo.value.id).toBe(3);
  });

  it('does not mark an ordinary quote or an unrelated warning', () => {
    context.contentAttributes.value = { unoapiWarnings: [{ code: 'OTHER' }] };
    expect(render().text()).not.toContain('Reference not sent');
  });
});
