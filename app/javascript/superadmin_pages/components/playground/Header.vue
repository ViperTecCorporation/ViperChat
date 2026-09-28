<script setup>
import { superAdminText } from '../../labels';
defineProps({
  responseSourcePath: {
    type: String,
    required: true,
  },
  responseSourceName: {
    type: String,
    required: true,
  },
});
</script>

<template>
  <header
    class="flex flex-wrap items-center gap-3 px-4 md:px-8 py-4 bg-white border-b border-slate-100"
    role="banner"
  >
    <a :href="responseSourcePath" class="text-woot-500 hover:underline mr-4">
      {{ superAdminText('back') }}
    </a>
    <div
      class="border border-solid border-slate-100 text-slate-700 mr-4 p-2 rounded-full"
    >
      <svg width="24" height="24"><use xlink:href="#icon-mist-fill" /></svg>
    </div>
    <div class="flex flex-col min-w-0 justify-center">
      <h1 id="page-title" class="text-base font-medium text-slate-900">
        {{ superAdminText('title') }}
      </h1>
      <p class="text-sm text-slate-600">
        {{ superAdminText('subtitle') }}
        <span class="font-medium">
          {{ responseSourceName }}
        </span>
      </p>
    </div>
  </header>
</template>
