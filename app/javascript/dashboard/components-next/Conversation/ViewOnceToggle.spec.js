import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import { useMediaQuery } from '@vueuse/core';
import ViewOnceToggle from './ViewOnceToggle.vue';

vi.mock('@vueuse/core', () => ({ useMediaQuery: vi.fn() }));

describe('ViewOnceToggle', () => {
  it.each([false, true])(
    'keeps the compact icon and restricts tooltip to desktop: %s',
    async desktop => {
      useMediaQuery.mockReturnValue(ref(desktop));
      const tooltip = vi.fn();
      const wrapper = mount(ViewOnceToggle, {
        global: {
          mocks: { $t: key => key },
          directives: {
            tooltip: { mounted: (_element, binding) => tooltip(binding.value) },
          },
        },
      });
      expect(wrapper.classes()).toContain('size-8');
      expect(wrapper.get('svg').classes()).toContain('size-5');
      expect(wrapper.text()).toBe('');
      expect(wrapper.attributes('aria-label')).toBe(
        'CONVERSATION.VIEW_ONCE_ENABLE'
      );
      expect(tooltip).toHaveBeenCalledWith({
        content: 'CONVERSATION.VIEW_ONCE_ENABLE',
        disabled: !desktop,
      });
      await wrapper.trigger('click');
      expect(wrapper.emitted('update:modelValue')).toEqual([[true]]);
      await wrapper.setProps({ modelValue: true, disabled: true });
      expect(wrapper.attributes('aria-pressed')).toBe('true');
      expect(wrapper.attributes('disabled')).toBeDefined();
      wrapper.unmount();
    }
  );
});
