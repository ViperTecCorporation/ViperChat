<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useToggle } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import ConversationRequiredAttributeItem from 'dashboard/components-next/ConversationWorkflow/ConversationRequiredAttributeItem.vue';
import ConversationRequiredEmpty from 'dashboard/components-next/Conversation/ConversationRequiredEmpty.vue';
import BasePaywallModal from 'dashboard/routes/dashboard/settings/components/BasePaywallModal.vue';
import {
  LEGACY_REQUIRED_ATTRIBUTE_SCOPE,
  normalizeRequiredAttributeRules,
  serializeRequiredAttributeRule,
} from 'dashboard/helper/conversationRequiredAttributes';

const props = defineProps({
  isEnabled: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['click']);
const router = useRouter();
const store = useStore();
const { t } = useI18n();
const { currentAccount, accountId, isOnChatwootCloud, updateAccount } =
  useAccount();
const [showDropdown, toggleDropdown] = useToggle(false);
const [isSaving, toggleSaving] = useToggle(false);
const selectedAttributeKey = ref('');
const selectedInboxId = ref('');
const applyToGroups = ref(false);
const conversationAttributes = useMapGetter(
  'attributes/getConversationAttributes'
);
const inboxes = useMapGetter('inboxes/getInboxes');
const currentUser = useMapGetter('getCurrentUser');

const isSuperAdmin = computed(() => currentUser.value.type === 'SuperAdmin');
const showPaywall = computed(() => !props.isEnabled && isOnChatwootCloud.value);
const i18nKey = computed(() =>
  isOnChatwootCloud.value ? 'PAYWALL' : 'ENTERPRISE_PAYWALL'
);

const goToBillingSettings = () => {
  router.push({
    name: 'billing_settings_index',
    params: { accountId: accountId.value },
  });
};

const handleClick = () => {
  emit('click');
};

onMounted(() => {
  store.dispatch('attributes/get');
  store.dispatch('inboxes/get');
});

const savedRequiredAttributes = computed(
  () => currentAccount.value?.settings?.conversation_required_attributes || []
);

const selectedAttributeRules = computed(() =>
  normalizeRequiredAttributeRules(savedRequiredAttributes.value)
);

const allAttributeOptions = computed(() =>
  (conversationAttributes.value || []).map(attribute => ({
    ...attribute,
    action: 'add',
    value: attribute.attributeKey,
    label: attribute.attributeDisplayName,
    type: attribute.attributeDisplayType,
  }))
);

const attributeOptions = computed(() => allAttributeOptions.value);

const inboxOptions = computed(() =>
  (inboxes.value || []).map(inbox => ({
    value: Number(inbox.id),
    label: inbox.name,
  }))
);

const selectedInbox = computed(() =>
  (inboxes.value || []).find(
    inbox => Number(inbox.id) === Number(selectedInboxId.value)
  )
);

const normalizedValue = value => (value || '').toString().toLowerCase();

const isUnoapiWhatsappInbox = inbox => {
  const channelType = normalizedValue(
    inbox?.channel_type || inbox?.channelType
  );
  const provider = normalizedValue(
    inbox?.provider || inbox?.providerName || inbox?.provider_name
  );

  return channelType.includes('whatsapp') && provider.includes('uno');
};

const showApplyToGroups = computed(() =>
  isUnoapiWhatsappInbox(selectedInbox.value)
);

watch(selectedInboxId, () => {
  applyToGroups.value = false;
});

const ruleExists = computed(() =>
  selectedAttributeRules.value.some(
    rule =>
      rule.scope !== LEGACY_REQUIRED_ATTRIBUTE_SCOPE &&
      rule.attributeKey === selectedAttributeKey.value &&
      Number(rule.inboxId) === Number(selectedInboxId.value)
  )
);

const canAddRule = computed(
  () => selectedAttributeKey.value && selectedInboxId.value && !ruleExists.value
);

const conversationRequiredAttributes = computed(() => {
  const attributeMap = new Map(
    allAttributeOptions.value.map(attr => [attr.value, attr])
  );
  const inboxMap = new Map(
    (inboxes.value || []).map(inbox => [Number(inbox.id), inbox.name])
  );

  return selectedAttributeRules.value
    .map(rule => {
      const attribute = attributeMap.get(rule.attributeKey);
      if (!attribute) return null;

      return {
        ...attribute,
        rule,
        value: rule.value,
        inboxName:
          rule.scope === LEGACY_REQUIRED_ATTRIBUTE_SCOPE
            ? t('CONVERSATION_WORKFLOW.REQUIRED_ATTRIBUTES.ITEM.LEGACY_SCOPE')
            : inboxMap.get(Number(rule.inboxId)),
        applyToGroups: rule.applyToGroups,
      };
    })
    .filter(Boolean);
});

const handleAddAttributesClick = event => {
  event.stopPropagation();
  toggleDropdown();
};

const resetForm = () => {
  selectedAttributeKey.value = '';
  selectedInboxId.value = '';
  applyToGroups.value = false;
};

const serializeRule = rule => {
  if (rule.scope === LEGACY_REQUIRED_ATTRIBUTE_SCOPE) {
    return rule.attributeKey;
  }

  return serializeRequiredAttributeRule(rule);
};

const saveRequiredAttributes = async rules => {
  try {
    toggleSaving(true);
    await updateAccount(
      { conversation_required_attributes: rules.map(serializeRule) },
      { silent: true }
    );
    useAlert(t('CONVERSATION_WORKFLOW.REQUIRED_ATTRIBUTES.SAVE.SUCCESS'));
    resetForm();
  } catch (error) {
    useAlert(t('CONVERSATION_WORKFLOW.REQUIRED_ATTRIBUTES.SAVE.ERROR'));
  } finally {
    toggleSaving(false);
    toggleDropdown(false);
  }
};

const handleAttributeAction = () => {
  if (!canAddRule.value || isSaving.value) return;
  const nextRule = {
    attributeKey: selectedAttributeKey.value,
    inboxId: Number(selectedInboxId.value),
    applyToGroups: showApplyToGroups.value ? applyToGroups.value : false,
    scope: 'inbox',
  };

  saveRequiredAttributes([...selectedAttributeRules.value, nextRule]);
};

const closeDropdown = () => {
  toggleDropdown(false);
};

const handleDelete = attribute => {
  if (isSaving.value) return;
  const updatedRules = selectedAttributeRules.value.filter(
    rule => rule.value !== attribute.rule.value
  );
  saveRequiredAttributes(updatedRules);
};
</script>

<template>
  <div
    v-if="isEnabled || showPaywall"
    class="flex flex-col w-full outline-1 outline outline-n-container rounded-xl bg-n-solid-2 divide-y divide-n-weak"
    @click="handleClick"
  >
    <div class="flex flex-col gap-2 items-start px-5 py-4">
      <div class="flex justify-between items-center w-full">
        <div class="flex flex-col gap-2">
          <h3 class="text-heading-2 text-n-slate-12">
            {{ $t('CONVERSATION_WORKFLOW.REQUIRED_ATTRIBUTES.TITLE') }}
          </h3>
          <p class="mb-0 text-body-para text-n-slate-11">
            {{ $t('CONVERSATION_WORKFLOW.REQUIRED_ATTRIBUTES.DESCRIPTION') }}
          </p>
        </div>
        <div v-if="isEnabled" v-on-clickaway="closeDropdown" class="relative">
          <Button
            icon="i-lucide-circle-plus"
            :label="$t('CONVERSATION_WORKFLOW.REQUIRED_ATTRIBUTES.ADD.TITLE')"
            :is-loading="isSaving"
            :disabled="
              isSaving ||
              attributeOptions.length === 0 ||
              inboxOptions.length === 0
            "
            @click="handleAddAttributesClick"
          />
          <div
            v-if="showDropdown"
            class="absolute top-full z-20 mt-2 flex w-[22rem] flex-col gap-3 rounded-lg border border-n-weak bg-n-solid-1 p-3 shadow-md ltr:right-0 rtl:left-0"
          >
            <Select
              v-model="selectedAttributeKey"
              class="w-full"
              :options="attributeOptions"
              :placeholder="
                $t(
                  'CONVERSATION_WORKFLOW.REQUIRED_ATTRIBUTES.ADD.ATTRIBUTE_PLACEHOLDER'
                )
              "
            />
            <Select
              v-model="selectedInboxId"
              class="w-full"
              :options="inboxOptions"
              :placeholder="
                $t(
                  'CONVERSATION_WORKFLOW.REQUIRED_ATTRIBUTES.ADD.INBOX_PLACEHOLDER'
                )
              "
            />
            <label
              v-if="showApplyToGroups"
              class="flex items-center gap-2 text-body-para text-n-slate-11"
            >
              <Checkbox v-model="applyToGroups" />
              <span>
                {{
                  $t(
                    'CONVERSATION_WORKFLOW.REQUIRED_ATTRIBUTES.ADD.APPLY_TO_GROUPS'
                  )
                }}
              </span>
            </label>
            <span v-if="ruleExists" class="text-body-para text-n-amber-11">
              {{
                $t(
                  'CONVERSATION_WORKFLOW.REQUIRED_ATTRIBUTES.ADD.ALREADY_EXISTS'
                )
              }}
            </span>
            <Button
              class="self-end"
              size="sm"
              :label="$t('CONVERSATION_WORKFLOW.REQUIRED_ATTRIBUTES.ADD.SAVE')"
              :disabled="!canAddRule || isSaving"
              :is-loading="isSaving"
              @click="handleAttributeAction"
            />
          </div>
        </div>
      </div>
    </div>

    <template v-if="isEnabled">
      <ConversationRequiredEmpty
        v-if="conversationRequiredAttributes.length === 0"
      />

      <ConversationRequiredAttributeItem
        v-for="attribute in conversationRequiredAttributes"
        :key="attribute.rule.value"
        :attribute="attribute"
        @delete="handleDelete"
      />
    </template>

    <BasePaywallModal
      v-else
      class="mx-auto my-8"
      feature-prefix="CONVERSATION_WORKFLOW.REQUIRED_ATTRIBUTES"
      :i18n-key="i18nKey"
      :is-on-chatwoot-cloud="isOnChatwootCloud"
      :is-super-admin="isSuperAdmin"
      @upgrade="goToBillingSettings"
    />
  </div>
</template>
