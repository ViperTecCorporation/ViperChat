import { shallowMount } from '@vue/test-utils';
import AttachmentsPreview from './AttachmentsPreview.vue';

describe('AttachmentsPreview', () => {
  it('keeps an unidentified document visible and removable', async () => {
    const attachment = { resource: { name: 'backup.7z', size: 1234 } };
    const wrapper = shallowMount(AttachmentsPreview, {
      props: { attachments: [attachment] },
    });
    expect(wrapper.text()).toContain('7Z');
    expect(wrapper.text()).toContain('backup.7z');
    await wrapper.findComponent({ name: 'Button' }).vm.$emit('click');
    expect(wrapper.emitted('removeAttachment')[0]).toEqual([[]]);
  });

  it('replaces an unsupported image preview with its extension', async () => {
    const wrapper = shallowMount(AttachmentsPreview, {
      props: {
        attachments: [
          {
            thumb: 'blob:photo',
            resource: {
              filename: 'photo.heic',
              content_type: 'image/heic',
              byte_size: 2048,
            },
          },
        ],
      },
    });
    await wrapper.find('img').trigger('error');
    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.text()).toContain('HEIC');
  });

  it('falls back to the video extension when its codec cannot be decoded', async () => {
    const wrapper = shallowMount(AttachmentsPreview, {
      props: {
        attachments: [
          {
            thumb: 'blob:video',
            resource: { name: 'clip.mov', type: 'video/quicktime', size: 2048 },
          },
        ],
      },
    });
    await wrapper.find('video').trigger('error');
    expect(wrapper.find('video').exists()).toBe(false);
    expect(wrapper.text()).toContain('MOV');
  });
});
