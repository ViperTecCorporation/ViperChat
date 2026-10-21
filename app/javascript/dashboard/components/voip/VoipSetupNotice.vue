<script setup>
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';

const { t } = useI18n();
const { accountScopedRoute } = useAccount();
</script>

<template>
  <section
    class="flex min-w-0 flex-col gap-3 rounded-xl border border-n-weak p-4"
  >
    <p class="text-sm text-n-slate-11">{{ t('AGENT_VOIP.LEGACY_NOTICE') }}</p>
    <router-link
      :to="accountScopedRoute('agent_voip_services')"
      class="min-h-11 self-start rounded-lg bg-n-brand px-4 py-3 text-white"
    >
      {{ t('AGENT_VOIP.SERVICES') }}
    </router-link>
  </section>
</template>
