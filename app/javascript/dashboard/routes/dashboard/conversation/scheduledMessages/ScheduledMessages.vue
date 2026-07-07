<template>
  <div class="flex flex-col gap-2 p-4">
    <h3 class="text-sm font-medium text-n-slate-12">
      {{ $t('SCHEDULED_MESSAGES.TITLE') }}
    </h3>
  </div>
</template>

<script>
export default {
  props: {
    conversationId: { type: Number, required: true },
    inboxId: { type: Number, required: true },
  },
};
</script>
