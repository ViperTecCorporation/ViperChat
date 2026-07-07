<template>
  <div
    class="flex flex-col gap-2 p-4 rounded-xl bg-n-alpha-2"
    :class="{ 'ring-2 ring-n-brand': active }"
    @click="$emit('click')"
  >
    <img :src="lightImage" :alt="title" class="block w-full dark:hidden" />
    <img :src="darkImage" :alt="title" class="hidden w-full dark:block" />
    <h3 class="text-sm font-medium text-n-slate-12">{{ title }}</h3>
    <p class="text-xs text-n-slate-11">{{ description }}</p>
  </div>
</template>

<script>
export default {
  props: {
    title: { type: String, required: true },
    description: { type: String, required: true },
    lightImage: { type: String, required: true },
    darkImage: { type: String, required: true },
    active: { type: Boolean, default: false },
  },
  emits: ['click'],
};
</script>
