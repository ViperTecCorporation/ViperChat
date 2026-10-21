<script setup>
import { reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength, email as emailRule } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  name: { type: String, default: '' },
  displayName: { type: String, default: '' },
  email: { type: String, default: '' },
  emailEnabled: { type: Boolean, default: false },
});
const emit = defineEmits(['updateUser']);
const { t } = useI18n();
const form = reactive({
  name: props.name,
  displayName: props.displayName,
  email: props.email,
});
watch(
  () => [props.name, props.displayName, props.email],
  ([name, displayName, email]) =>
    Object.assign(form, { name, displayName, email })
);
const v$ = useVuelidate(
  {
    name: { required, minLength: minLength(1) },
    email: { required, emailRule },
  },
  form
);
async function save() {
  if (!(await v$.value.$validate())) {
    useAlert(t('PROFILE_SETTINGS.FORM.ERROR'));
    return;
  }
  emit('updateUser', {
    name: form.name,
    displayName: form.displayName,
    email: form.email,
  });
}
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="save">
    <label class="flex flex-col gap-1 text-sm">
      {{ t('PROFILE_SETTINGS.FORM.NAME.LABEL') }}
      <input
        v-model="form.name"
        required
        class="rounded-xl border border-n-weak bg-n-surface-1 px-3 py-2"
        :aria-invalid="v$.name.$error"
        @blur="v$.name.$touch"
      />
    </label>
    <p v-if="v$.name.$error" class="text-sm text-n-ruby-11">
      {{ t('PROFILE_SETTINGS.FORM.NAME.ERROR') }}
    </p>
    <label class="flex flex-col gap-1 text-sm">
      {{ t('PROFILE_SETTINGS.FORM.DISPLAY_NAME.LABEL') }}
      <input
        v-model="form.displayName"
        class="rounded-xl border border-n-weak bg-n-surface-1 px-3 py-2"
      />
    </label>
    <label v-if="emailEnabled" class="flex flex-col gap-1 text-sm">
      {{ t('PROFILE_SETTINGS.FORM.EMAIL.LABEL') }}
      <input
        v-model="form.email"
        type="email"
        required
        class="rounded-xl border border-n-weak bg-n-surface-1 px-3 py-2"
        :aria-invalid="v$.email.$error"
        @blur="v$.email.$touch"
      />
    </label>
    <p v-if="v$.email.$error" class="text-sm text-n-ruby-11">
      {{ t('PROFILE_SETTINGS.FORM.EMAIL.ERROR') }}
    </p>
    <div>
      <NextButton type="submit" :label="t('PROFILE_SETTINGS.BTN_TEXT')" />
    </div>
  </form>
</template>
