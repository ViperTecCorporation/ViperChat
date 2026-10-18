<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAdmin } from 'dashboard/composables/useAdmin';
import API from 'dashboard/api/whatsappTemplates';
import {
  newTemplateDraft,
  templateVariables,
  validateTemplate,
  templatePayload,
  previewTemplate,
  templateError,
  matchesTemplate,
} from './whatsappTemplateHelper';

const props = defineProps({
  inboxId: { type: Number, required: true },
  active: { type: Boolean, default: true },
});
const { t } = useI18n();
const { isAdmin } = useAdmin();
const label = (key, values) => t(`WHATSAPP_TEMPLATE_CREATION.${key}`, values);
const draft = reactive(newTemplateDraft());
const templates = ref([]);
const lastUpdated = ref(null);
const loaded = ref(false);
const loading = ref(false);
const creating = ref(false);
const syncing = ref(false);
const uncertain = ref(false);
const error = ref('');
const providerMessage = ref('');
const result = ref(null);
const buttonType = ref('QUICK_REPLY');
const variables = computed(() => templateVariables(draft.body));
const errors = computed(() => validateTemplate(draft));
const preview = computed(() => previewTemplate(draft));
const busy = computed(() => loading.value || creating.value || syncing.value);
const locked = computed(() => busy.value || uncertain.value || !!result.value);
let generation = 0;

function providerDetails(failure) {
  const details = failure.response?.data || {};
  return [
    details.provider_message,
    details.provider_code != null
      ? label('PROVIDER_CODE', { code: details.provider_code })
      : '',
  ]
    .filter(Boolean)
    .join(' — ');
}

function receive(data) {
  templates.value = data.templates;
  lastUpdated.value = data.last_updated_at;
  loaded.value = true;
}

async function load(sync = false) {
  if (!isAdmin.value || busy.value) return;
  const current = generation;
  error.value = '';
  providerMessage.value = '';
  if (sync) syncing.value = true;
  else loading.value = true;
  try {
    const { data } = await (sync
      ? API.sync(props.inboxId)
      : API.get(props.inboxId));
    if (current !== generation) return;
    receive(data);
    if (sync && (uncertain.value || result.value)) {
      const match = templates.value.find(template =>
        matchesTemplate(template, draft)
      );
      if (match) {
        result.value = match;
        uncertain.value = false;
      }
    }
  } catch (failure) {
    if (current === generation) {
      error.value = templateError(failure);
      providerMessage.value = providerDetails(failure);
    }
  } finally {
    if (current === generation) {
      loading.value = false;
      syncing.value = false;
    }
  }
}

async function create() {
  if (!isAdmin.value || locked.value || errors.value.length) return;
  creating.value = true;
  error.value = '';
  providerMessage.value = '';
  const current = generation;
  try {
    const { data } = await API.create(props.inboxId, templatePayload(draft));
    if (current !== generation) return;
    result.value = data.template;
    // Preserve the provider's status, never infer approval from HTTP 201.
    templates.value = [
      data.template,
      ...templates.value.filter(item => item.id !== data.template.id),
    ];
  } catch (failure) {
    if (current !== generation) return;
    error.value = templateError(failure, true);
    providerMessage.value = providerDetails(failure);
    uncertain.value = error.value === 'outcome_unknown';
  } finally {
    if (current === generation) creating.value = false;
  }
}

function addButton() {
  if (locked.value) return;
  const type = draft.buttons[0]?.type || buttonType.value;
  if (draft.buttons.length < (type === 'URL' ? 2 : 3)) {
    draft.buttons.push({
      type,
      text: '',
      ...(type === 'URL' ? { url: '' } : {}),
    });
  }
}

function reset() {
  if (busy.value || uncertain.value) return;
  Object.assign(draft, newTemplateDraft());
  result.value = null;
  error.value = '';
  providerMessage.value = '';
}

watch(
  () => props.inboxId,
  () => {
    generation += 1;
    Object.assign(draft, newTemplateDraft());
    templates.value = [];
    result.value = null;
    uncertain.value = false;
    loaded.value = false;
    loading.value = false;
    creating.value = false;
    syncing.value = false;
    error.value = '';
    providerMessage.value = '';
  }
);
watch(
  [() => props.active, () => props.inboxId, isAdmin],
  () => {
    if (props.active && !loaded.value && isAdmin.value) load();
  },
  { immediate: true }
);
</script>

<template>
  <section
    v-if="isAdmin"
    class="min-w-0 px-3 sm:px-6 pb-[max(1.5rem,env(safe-area-inset-bottom))] text-n-slate-12"
    :aria-busy="busy"
  >
    <h2 class="text-lg font-medium">{{ label('TITLE') }}</h2>
    <p class="text-sm text-n-slate-11">{{ label('HELP') }}</p>
    <a
      class="text-sm text-n-blue-11 underline"
      href="https://business.facebook.com/wa/manage/message-templates/"
      target="_blank"
      rel="noopener noreferrer"
      >{{ label('META_MANAGER') }}</a
    >
    <div class="flex flex-wrap items-center gap-3 my-4">
      <button
        type="button"
        class="button small"
        :disabled="busy"
        @click="load(true)"
      >
        {{ label(syncing ? 'SYNCING' : 'SYNC') }}
      </button>
      <button
        v-if="!loaded && !loading"
        type="button"
        class="button small secondary"
        :disabled="busy"
        @click="load()"
      >
        {{ label('RELOAD') }}
      </button>
      <span v-if="loading" role="status">{{ label('LOADING') }}</span>
      <span v-if="lastUpdated" class="text-sm break-all">{{
        label('LAST_UPDATED', { date: lastUpdated })
      }}</span>
    </div>
    <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
      {{ label(`ERRORS.${error}`) }}
    </p>
    <p
      v-if="error && providerMessage"
      data-test="provider-message"
      class="text-sm text-n-ruby-11 break-words [overflow-wrap:anywhere]"
    >
      {{ providerMessage }}
    </p>
    <p
      v-if="uncertain"
      role="alert"
      class="p-3 rounded-lg bg-n-amber-3 text-n-amber-11"
    >
      {{ label('UNCERTAIN') }}
    </p>
    <p
      v-if="result"
      role="status"
      class="p-3 rounded-lg bg-n-slate-3 break-words"
    >
      {{
        label('CREATED', {
          name: result.name,
          status: result.status || label('STATUS_UNKNOWN'),
        })
      }}
    </p>
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 min-w-0">
      <form class="min-w-0" @submit.prevent="create">
        <fieldset
          :disabled="locked"
          class="flex flex-col gap-4 min-w-0 m-0 p-0 border-0"
        >
          <legend class="mb-3 font-medium">{{ label('NEW') }}</legend>
          <label
            >{{ label('NAME')
            }}<input
              v-model="draft.name"
              data-test="name"
              class="w-full min-w-0 text-base"
              maxlength="512"
              autocomplete="off"
              autocapitalize="none"
              spellcheck="false"
              required
          /></label>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <label
              >{{ label('CATEGORY')
              }}<select v-model="draft.category" class="w-full text-base">
                <option value="UTILITY">{{ label('UTILITY') }}</option>
                <option value="MARKETING">{{ label('MARKETING') }}</option>
              </select></label
            >
            <label
              >{{ label('LANGUAGE')
              }}<select v-model="draft.language" class="w-full text-base">
                <option value="pt_BR">{{ label('PT_BR') }}</option>
                <option value="en_US">{{ label('EN_US') }}</option>
                <option value="es">{{ label('ES') }}</option>
              </select></label
            >
          </div>
          <label
            >{{ label('HEADER')
            }}<input
              v-model="draft.header"
              data-test="header"
              class="w-full text-base"
              maxlength="60"
          /></label>
          <label
            >{{ label('BODY')
            }}<textarea
              v-model="draft.body"
              data-test="body"
              class="w-full text-base"
              rows="5"
              maxlength="1024"
              required
            /><span class="text-xs text-n-slate-11"
              >{{
                label('BODY_COUNT', { count: Array.from(draft.body).length })
              }}
              {{ label('VARIABLE_HELP') }}</span
            ></label
          >
          <div v-for="variable in variables" :key="variable">
            <label
              >{{ label('EXAMPLE', { number: variable })
              }}<input
                v-model="draft.examples[variable - 1]"
                :data-test="`example-${variable}`"
                class="w-full text-base"
                maxlength="1024"
                required
            /></label>
          </div>
          <label
            >{{ label('FOOTER')
            }}<input
              v-model="draft.footer"
              class="w-full text-base"
              maxlength="60"
          /></label>
          <div class="flex flex-col gap-3 min-w-0">
            <label
              >{{ label('BUTTON_TYPE')
              }}<select
                v-model="buttonType"
                :disabled="draft.buttons.length > 0"
                class="w-full text-base"
              >
                <option value="QUICK_REPLY">{{ label('QUICK_REPLY') }}</option>
                <option value="URL">{{ label('URL') }}</option>
              </select></label
            >
            <div
              v-for="(button, index) in draft.buttons"
              :key="index"
              class="flex flex-col gap-2 min-w-0 p-3 border border-n-weak rounded-lg"
            >
              <label
                >{{ label('BUTTON_TEXT')
                }}<input
                  v-model="button.text"
                  class="w-full text-base"
                  maxlength="25"
                  required
              /></label>
              <label v-if="button.type === 'URL'"
                >{{ label('BUTTON_URL')
                }}<input
                  v-model="button.url"
                  type="url"
                  maxlength="2000"
                  class="w-full text-base"
                  required
              /></label>
              <button
                type="button"
                class="button small secondary self-start"
                @click="draft.buttons.splice(index, 1)"
              >
                {{ label('REMOVE') }}
              </button>
            </div>
            <button
              type="button"
              class="button small secondary self-start"
              :disabled="
                draft.buttons.length >=
                ((draft.buttons[0]?.type || buttonType) === 'URL' ? 2 : 3)
              "
              @click="addButton"
            >
              {{ label('ADD_BUTTON') }}
            </button>
          </div>
          <ul
            v-if="errors.length"
            class="text-sm text-n-slate-11 pl-4"
            aria-live="polite"
          >
            <li v-for="code in errors" :key="code">
              {{ label(`VALIDATION.${code}`) }}
            </li>
          </ul>
          <button
            type="submit"
            class="button w-full sm:w-auto sm:self-start min-h-11"
            :disabled="locked || errors.length > 0"
          >
            {{ label(creating ? 'CREATING' : 'SUBMIT') }}
          </button>
        </fieldset>
        <button
          v-if="result"
          type="button"
          class="button secondary mt-4"
          :disabled="busy"
          @click="reset"
        >
          {{ label('NEW') }}
        </button>
      </form>
      <aside class="min-w-0">
        <h3 class="text-base font-medium">{{ label('PREVIEW') }}</h3>
        <div
          class="p-4 rounded-xl border border-n-weak bg-n-slate-2 min-w-0 break-words [overflow-wrap:anywhere]"
        >
          <p class="font-medium whitespace-pre-wrap">{{ draft.header }}</p>
          <p data-test="preview" class="whitespace-pre-wrap">{{ preview }}</p>
          <p class="text-sm text-n-slate-11 whitespace-pre-wrap">
            {{ draft.footer }}
          </p>
          <p
            v-for="(button, index) in draft.buttons"
            :key="index"
            class="text-n-blue-11 border-t border-n-weak pt-2"
          >
            {{ button.text
            }}<span v-if="button.type === 'URL'" class="block text-xs">{{
              button.url
            }}</span>
          </p>
        </div>
      </aside>
    </div>
    <h3 class="mt-8 text-base font-medium">{{ label('CACHED') }}</h3>
    <p v-if="loaded && !templates.length" class="text-sm text-n-slate-11">
      {{ label('EMPTY') }}
    </p>
    <ul class="list-none p-0 flex flex-col gap-2">
      <li
        v-for="template in templates"
        :key="`${template.id}-${template.name}-${template.language}`"
        class="p-3 border border-n-weak rounded-lg min-w-0 break-words [overflow-wrap:anywhere]"
      >
        <span class="font-medium">{{ template.name }}</span>
        <span class="block text-sm text-n-slate-11"
          >{{ template.language }} · {{ template.category }} ·
          {{ template.status || label('STATUS_UNKNOWN') }}</span
        >
      </li>
    </ul>
  </section>
</template>
