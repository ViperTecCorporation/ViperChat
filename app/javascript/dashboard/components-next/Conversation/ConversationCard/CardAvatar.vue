<script setup>
import { ref, computed } from 'vue';
import Avatar from 'next/avatar/Avatar.vue';
import AvatarPreview from 'dashboard/components-next/avatar/AvatarPreview.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

const props = defineProps({
  contact: { type: Object, required: true },
  selected: { type: Boolean, default: false },
  enableSelection: { type: Boolean, default: true },
  hideThumbnail: { type: Boolean, default: false },
});

const emit = defineEmits(['selectConversation']);

const hovered = ref(false);

const onThumbnailHover = () => {
  hovered.value = !props.hideThumbnail;
};

const onThumbnailLeave = () => {
  hovered.value = false;
};

const selectedModel = computed({
  get: () => props.selected,
  set: value => {
    emit('selectConversation', value);
  },
});
</script>

<template>
  <div
    class="relative flex items-center flex-shrink-0"
    @mouseenter="onThumbnailHover"
    @mouseleave="onThumbnailLeave"
  >
    <AvatarPreview
      v-if="!hideThumbnail"
      :name="contact.name"
      :src="contact.thumbnail"
    >
      <Avatar
        :name="contact.name"
        :src="contact.thumbnail"
        :size="24"
        :status="contact.availability_status"
        hide-offline-status
      />
    </AvatarPreview>
    <div
      v-if="!hideThumbnail && enableSelection && (hovered || selected)"
      class="absolute -bottom-2 ltr:-right-1 rtl:-left-1 z-10 rounded bg-n-background"
      @click.stop
    >
      <Checkbox v-model="selectedModel" />
    </div>
  </div>
</template>
