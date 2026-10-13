<script setup>
import UnoapiSettingLabel from './UnoapiSettingLabel.vue';

const model = defineModel({ type: String, default: '' });
</script>

<template>
  <label class="flex min-w-0 flex-col gap-1 text-sm text-n-slate-11">
    <UnoapiSettingLabel
      :label="$t('INBOX_MGMT.ADD.WHATSAPP.CLIENT_PROFILE.LABEL')"
      :help="$t('INBOX_MGMT.ADD.WHATSAPP.CLIENT_PROFILE.HELP')"
    />
    <select v-model="model" class="w-full min-w-0 rounded-md border-n-strong">
      <option value="">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.CLIENT_PROFILE.DEFAULT') }}
      </option>
      <option value="wa_personal">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.CLIENT_PROFILE.PERSONAL') }}
      </option>
      <option value="wa_business">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.CLIENT_PROFILE.BUSINESS') }}
      </option>
    </select>
  </label>
</template>
