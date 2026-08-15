<script setup>
import { computed } from 'vue';
import router from '../../routes/index';
const props = defineProps({
  backUrl: {
    type: [String, Object],
    default: '',
  },
  buttonLabel: {
    type: String,
    default: '',
  },
  compact: {
    type: Boolean,
    default: false,
  },
  iconOnly: {
    type: Boolean,
    default: false,
  },
  mobileIconOnly: {
    type: Boolean,
    default: false,
  },
  badgeCount: {
    type: Number,
    default: 0,
  },
  accessibleLabel: {
    type: String,
    default: '',
  },
});

const goBack = () => {
  if (props.backUrl !== '') {
    router.push(props.backUrl);
  } else {
    router.go(-1);
  }
};

const buttonStyleClass = props.compact ? 'text-sm' : 'text-base';
const ariaLabel = computed(() => {
  const label = props.accessibleLabel || props.buttonLabel;
  const count = props.badgeCount > 0 ? ` (${props.badgeCount})` : '';
  return label ? `${label}${count}` : '';
});
const badgeText = computed(() =>
  props.badgeCount > 99 ? '99+' : String(props.badgeCount)
);
</script>

<template>
  <button
    class="relative flex items-center p-0 font-normal cursor-pointer text-n-slate-11"
    :class="[
      buttonStyleClass,
      iconOnly &&
        'justify-center flex-shrink-0 size-8 rounded-lg hover:bg-n-alpha-2',
      mobileIconOnly &&
        'justify-center flex-shrink-0 size-8 rounded-lg hover:bg-n-alpha-2 sm:size-auto sm:justify-start sm:rounded-none sm:hover:bg-transparent',
    ]"
    :aria-label="ariaLabel || undefined"
    @click.capture="goBack"
  >
    <i
      class="i-lucide-chevron-left text-lg"
      :class="!iconOnly && !mobileIconOnly && '-ml-1'"
    />
    <span v-if="!iconOnly" :class="mobileIconOnly && 'hidden sm:inline'">
      {{ buttonLabel || $t('GENERAL_SETTINGS.BACK') }}
    </span>
    <span
      v-if="(iconOnly || mobileIconOnly) && badgeCount > 0"
      class="absolute -right-1.5 -top-1.5 min-w-5 h-5 px-1 grid place-items-center rounded-full border-2 border-n-solid-1 bg-n-brand text-[10px] font-semibold leading-none text-white"
      :class="mobileIconOnly && 'sm:hidden'"
    >
      {{ badgeText }}
    </span>
  </button>
</template>
