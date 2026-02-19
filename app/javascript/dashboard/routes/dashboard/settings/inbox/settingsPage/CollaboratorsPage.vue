<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { vOnClickOutside } from '@vueuse/components';
import { useVuelidate } from '@vuelidate/core';
import { minValue } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { useConfig } from 'dashboard/composables/useConfig';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import SettingsAccordion from 'dashboard/components-next/Settings/SettingsAccordion.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';

export default {
  components: {
    SettingsSection,
    NextButton,
    Input,
  },
});

    return { v$: useVuelidate(), isEnterprise };
  },
  data() {
    return {
      selectedAgents: [],
      isAgentListUpdating: false,
      isCredentialsUpdating: false,
      enableAutoAssignment: false,
      maxAssignmentLimit: null,
      agentCredentials: {},
      initialAgentCredentials: {},
    };
  },
  computed: {
    ...mapGetters({
      agentList: 'agents/getAgents',
    }),
    isCustomVoiceChannel() {
      return (
        this.inbox.channel_type === 'Channel::Voice' &&
        this.inbox.provider === 'custom'
      );
    },
    maxAssignmentLimitErrors() {
      if (this.v$.maxAssignmentLimit.$error) {
        return this.$t(
          'INBOX_MGMT.AUTO_ASSIGNMENT.MAX_ASSIGNMENT_LIMIT_RANGE_ERROR'
        );
      }
      return '';
    },
  },
  watch: {
    inbox() {
      this.setDefaults();
    },
    selectedAgents: {
      handler() {
        this.ensureCredentialEntries();
      },
      deep: true,
    },
  },
  mounted() {
    this.setDefaults();
  },
  methods: {
    setDefaults() {
      this.enableAutoAssignment = this.inbox.enable_auto_assignment;
      this.maxAssignmentLimit =
        this.inbox?.auto_assignment_config?.max_assignment_limit || null;
      this.fetchAttachedAgents();
    },
    async fetchAttachedAgents() {
      try {
        // eslint-disable-next-line no-console
        console.log('[VoiceCredentials] fetchAttachedAgents', {
          inboxId: this.inbox.id,
        });
        const response = await this.$store.dispatch('inboxMembers/get', {
          inboxId: this.inbox.id,
        });
        const {
          data: { payload: inboxMembers },
        } = response;
        this.selectedAgents = inboxMembers;
        this.setCredentialDefaults(inboxMembers);
      } catch (error) {
        //  Handle error
      }
    },
    setCredentialDefaults(inboxMembers) {
      const credentials = {};
      const initialCredentials = {};
      inboxMembers.forEach(agent => {
        const member = agent.inbox_member || {};
        const webrtcUsername = member.webrtc_username || '';
        credentials[agent.id] = {
          webrtcUsername,
          webrtcJwt: '',
          webrtcPassword: '',
          hasWebrtcJwt: !!member.has_webrtc_jwt,
          hasWebrtcPassword: !!member.has_webrtc_password,
        };
        initialCredentials[agent.id] = { webrtcUsername };
      });
      this.agentCredentials = credentials;
      this.initialAgentCredentials = initialCredentials;
    },
    ensureCredentialEntries() {
      this.selectedAgents.forEach(agent => {
        if (!this.agentCredentials[agent.id]) {
          this.agentCredentials[agent.id] = {
            webrtcUsername: '',
            webrtcJwt: '',
            webrtcPassword: '',
            hasWebrtcJwt: false,
            hasWebrtcPassword: false,
          };
        }
        if (!this.initialAgentCredentials[agent.id]) {
          this.initialAgentCredentials[agent.id] = { webrtcUsername: '' };
        }
      });
    },
    handleEnableAutoAssignment() {
      this.updateInbox();
    },
    async updateAgents() {
      const agentList = this.selectedAgents.map(el => el.id);
      this.isAgentListUpdating = true;
      try {
        // eslint-disable-next-line no-console
        console.log('[VoiceCredentials] updateAgents', {
          inboxId: this.inbox.id,
          agentCount: agentList.length,
        });
        await this.$store.dispatch('inboxMembers/create', {
          inboxId: this.inbox.id,
          agentList,
        });
        useAlert(this.$t('AGENT_MGMT.EDIT.API.SUCCESS_MESSAGE'));
        await this.fetchAttachedAgents();
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error('[VoiceCredentials] updateAgents error', { error });
        useAlert(this.$t('AGENT_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
      this.isAgentListUpdating = false;
    },
    buildMemberAttributesPayload() {
      return this.selectedAgents
        .map(agent => {
          const credentials = this.agentCredentials[agent.id] || {};
          const initial = this.initialAgentCredentials[agent.id] || {};
          const payload = { user_id: agent.id };
          let hasChanges = false;

          if (credentials.webrtcUsername !== initial.webrtcUsername) {
            payload.webrtc_username = credentials.webrtcUsername;
            hasChanges = true;
          }

          if (credentials.webrtcJwt) {
            payload.webrtc_jwt = credentials.webrtcJwt;
            hasChanges = true;
          }

          if (credentials.webrtcPassword) {
            payload.webrtc_password = credentials.webrtcPassword;
            hasChanges = true;
          }

          return hasChanges ? payload : null;
        })
        .filter(Boolean);
    },
    async updateVoiceAgentCredentials() {
      const memberAttributes = this.buildMemberAttributesPayload();
      if (!memberAttributes.length) return;

      this.isCredentialsUpdating = true;
      try {
        // eslint-disable-next-line no-console
        console.log('[VoiceCredentials] updateCredentials', {
          inboxId: this.inbox.id,
          memberAttributesCount: memberAttributes.length,
        });
        await this.$store.dispatch('inboxMembers/updateCredentials', {
          inboxId: this.inbox.id,
          memberAttributes,
        });
        memberAttributes.forEach(
          ({
            user_id: userId,
            webrtc_username: username,
            webrtc_jwt: jwt,
            webrtc_password: password,
          }) => {
            if (username !== undefined) {
              this.initialAgentCredentials[userId] = {
                webrtcUsername: username,
              };
            }
            if (jwt) {
              const current = this.agentCredentials[userId] || {};
              this.agentCredentials[userId] = {
                ...current,
                webrtcJwt: '',
                hasWebrtcJwt: true,
              };
            }
            if (password) {
              const current = this.agentCredentials[userId] || {};
              this.agentCredentials[userId] = {
                ...current,
                webrtcPassword: '',
                hasWebrtcPassword: true,
              };
            }
          }
        );
        useAlert(
          this.$t('INBOX_MGMT.SETTINGS_POPUP.VOICE_AGENT_CREDENTIALS_SUCCESS')
        );
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error('[VoiceCredentials] updateCredentials error', { error });
        useAlert(
          this.$t('INBOX_MGMT.SETTINGS_POPUP.VOICE_AGENT_CREDENTIALS_ERROR')
        );
      } finally {
        this.isCredentialsUpdating = false;
      }
    },
    async updateInbox() {
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          enable_auto_assignment: this.enableAutoAssignment,
          auto_assignment_config: {
            max_assignment_limit: this.maxAssignmentLimit,
          },
        };
        // eslint-disable-next-line no-console
        console.log('[VoiceCredentials] updateInbox', {
          inboxId: this.inbox.id,
          enableAutoAssignment: this.enableAutoAssignment,
          maxAssignmentLimit: this.maxAssignmentLimit,
        });
        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error('[VoiceCredentials] updateInbox error', { error });
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      }
    },
  },
  validations: {
    selectedAgents: {
      isEmpty() {
        return !!this.selectedAgents.length;
      },
    },
    maxAssignmentLimit: {
      minValue: minValue(1),
    },
  },
};

const v$ = useVuelidate(rules, { maxAssignmentLimit });

const assignmentHeader = computed(() =>
  hasAssignmentV2.value
    ? t('INBOX_MGMT.ASSIGNMENT.ENABLE_AUTO_ASSIGNMENT')
    : t('INBOX_MGMT.SETTINGS_POPUP.AUTO_ASSIGNMENT')
);

const assignmentDescription = computed(() =>
  hasAssignmentV2.value
    ? t('INBOX_MGMT.ASSIGNMENT.DESCRIPTION')
    : t('INBOX_MGMT.SETTINGS_POPUP.AUTO_ASSIGNMENT_SUB_TEXT')
);

const maxAssignmentLimitErrors = computed(() => {
  if (v$.value.maxAssignmentLimit.$error) {
    return t('INBOX_MGMT.AUTO_ASSIGNMENT.MAX_ASSIGNMENT_LIMIT_RANGE_ERROR');
  }
  return '';
});

const fetchAttachedAgents = async () => {
  try {
    const response = await store.dispatch('inboxMembers/get', {
      inboxId: props.inbox.id,
    });
    const {
      data: { payload: inboxMembers },
    } = response;
    selectedAgentIds.value = inboxMembers.map(m => m.id);
  } catch (error) {
    //  Handle error
  }
};

const fetchAssignmentPolicy = async () => {
  if (!props.inbox.id) return;

  isLoadingPolicy.value = true;
  try {
    const response = await assignmentPoliciesAPI.getInboxPolicy(props.inbox.id);
    assignmentPolicy.value = response.data;
  } catch (error) {
    // No policy attached, which is fine
    assignmentPolicy.value = null;
  } finally {
    isLoadingPolicy.value = false;
  }
};

const fetchAvailablePolicies = async () => {
  isLoadingPolicies.value = true;
  try {
    const response = await assignmentPoliciesAPI.get();
    availablePolicies.value = response.data;
  } catch (error) {
    availablePolicies.value = [];
  } finally {
    isLoadingPolicies.value = false;
  }
};

const linkPolicyToInbox = async policy => {
  isLinkingPolicy.value = true;
  try {
    await assignmentPoliciesAPI.setInboxPolicy(props.inbox.id, policy.id);
    assignmentPolicy.value = policy;
    showPolicyDropdown.value = false;
    useAlert(t('INBOX_MGMT.ASSIGNMENT.LINK_SUCCESS'));
  } catch (error) {
    useAlert(t('INBOX_MGMT.ASSIGNMENT.LINK_ERROR'));
  } finally {
    isLinkingPolicy.value = false;
  }
};

const navigateToAssignmentPolicies = () => {
  const accountId = route.params.accountId;
  router.push({
    name: 'agent_assignment_policy_index',
    params: { accountId },
  });
};

const policyMenuItems = computed(() => {
  const items = availablePolicies.value.map(policy => ({
    action: 'select_policy',
    value: policy.id,
    label: policy.name,
    icon: 'i-lucide-zap',
    policy,
  }));

  items.push({
    action: 'view_all',
    value: 'view_all',
    label: t('INBOX_MGMT.ASSIGNMENT.VIEW_ALL_POLICIES'),
    icon: 'i-lucide-arrow-right',
  });

  return items;
});

const handlePolicyMenuAction = ({ action, policy }) => {
  if (action === 'select_policy' && policy) {
    linkPolicyToInbox(policy);
  } else if (action === 'view_all') {
    navigateToAssignmentPolicies();
  }
  showPolicyDropdown.value = false;
};

const togglePolicyDropdown = () => {
  if (!showPolicyDropdown.value && availablePolicies.value.length === 0) {
    fetchAvailablePolicies();
  }
  showPolicyDropdown.value = !showPolicyDropdown.value;
};

const closePolicyDropdown = () => {
  showPolicyDropdown.value = false;
};

const handleToggleAutoAssignment = async val => {
  enableAutoAssignment.value = val;
  try {
    const payload = {
      id: props.inbox.id,
      formData: false,
      enable_auto_assignment: val,
    };
    await store.dispatch('inboxes/updateInbox', payload);
    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
  }
};

const updateAgents = async () => {
  isAgentListUpdating.value = true;
  try {
    await store.dispatch('inboxMembers/create', {
      inboxId: props.inbox.id,
      agentList: selectedAgentIds.value,
    });
    useAlert(t('AGENT_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('AGENT_MGMT.EDIT.API.ERROR_MESSAGE'));
  }
  isAgentListUpdating.value = false;
};

const updateInbox = async () => {
  try {
    const payload = {
      id: props.inbox.id,
      formData: false,
      enable_auto_assignment: enableAutoAssignment.value,
      auto_assignment_config: {
        max_assignment_limit: maxAssignmentLimit.value,
      },
    };
    await store.dispatch('inboxes/updateInbox', payload);
    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
  }
};

const navigateToCreatePolicy = () => {
  const accountId = route.params.accountId;
  router.push({
    name: 'agent_assignment_policy_create',
    params: { accountId },
    query: { inboxId: props.inbox.id },
  });
};

const navigateToAssignmentPolicyEdit = () => {
  if (!assignmentPolicy.value?.id) return;
  const accountId = route.params.accountId;
  router.push({
    name: 'agent_assignment_policy_edit',
    params: { accountId, id: assignmentPolicy.value.id },
  });
};

const navigateToBilling = () => {
  const accountId = route.params.accountId;
  router.push({
    name: 'billing_settings_index',
    params: { accountId },
  });
};

const confirmDeletePolicy = () => {
  showDeleteConfirmModal.value = true;
};

const cancelDeletePolicy = () => {
  showDeleteConfirmModal.value = false;
};

const deleteAssignmentPolicy = async () => {
  if (isDeletingPolicy.value) return;
  isDeletingPolicy.value = true;
  try {
    await assignmentPoliciesAPI.removeInboxPolicy(props.inbox.id);
    assignmentPolicy.value = null;
    showDeleteConfirmModal.value = false;
    useAlert(t('INBOX_MGMT.ASSIGNMENT_POLICY.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(t('INBOX_MGMT.ASSIGNMENT_POLICY.DELETE_ERROR'));
  } finally {
    isDeletingPolicy.value = false;
  }
};

const setDefaults = () => {
  enableAutoAssignment.value = props.inbox.enable_auto_assignment;
  maxAssignmentLimit.value =
    props.inbox.auto_assignment_config?.max_assignment_limit || null;
  fetchAttachedAgents();
  if (showAdvancedAssignmentUI.value) {
    fetchAssignmentPolicy();
    fetchAvailablePolicies();
  }
};

// Watch only inbox.id to avoid unnecessary refetches when other properties change
watch(() => props.inbox.id, setDefaults);

onMounted(() => {
  setDefaults();
});
</script>

<template>
  <div>
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.INBOX_AGENTS')"
      :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.INBOX_AGENTS_SUB_TEXT')"
      class="[&>div]:!items-start"
    >
      <div
        class="rounded-xl outline outline-1 -outline-offset-1 outline-n-weak hover:outline-n-strong px-2 py-2"
      >
        <TagInput
          :model-value="selectedAgentNames"
          :placeholder="$t('INBOX_MGMT.ADD.AGENTS.PICK_AGENTS')"
          :menu-items="agentMenuItems"
          show-dropdown
          skip-label-dedup
          :auto-open-dropdown="false"
          @add="handleAgentAdd"
          @remove="handleAgentRemove"
        />
      </div>

      <NextButton
        :label="$t('INBOX_MGMT.SETTINGS_POPUP.UPDATE')"
        :is-loading="isAgentListUpdating"
        @click="updateAgents"
      />
    </SettingsSection>

    <SettingsSection
      v-if="isCustomVoiceChannel && selectedAgents.length"
      :title="$t('INBOX_MGMT.SETTINGS_POPUP.VOICE_AGENT_CREDENTIALS_TITLE')"
      :sub-title="$t('INBOX_MGMT.SETTINGS_POPUP.VOICE_AGENT_CREDENTIALS_SUB_TEXT')"
    >
      <div class="flex flex-col gap-4">
        <div
          v-for="agent in selectedAgents"
          :key="agent.id"
          class="flex flex-col gap-2 p-4 rounded-lg border border-n-strong"
        >
          <div class="text-sm font-medium text-n-slate-12">
            {{ agent.name }}
          </div>
          <Input
            v-model="agentCredentials[agent.id].webrtcUsername"
            :label="
              $t('INBOX_MGMT.SETTINGS_POPUP.VOICE_AGENT_CREDENTIALS_USERNAME_LABEL')
            "
            :placeholder="
              $t(
                'INBOX_MGMT.SETTINGS_POPUP.VOICE_AGENT_CREDENTIALS_USERNAME_PLACEHOLDER'
              )
            "
          />
          <Input
            v-model="agentCredentials[agent.id].webrtcJwt"
            type="password"
            :label="
              $t('INBOX_MGMT.SETTINGS_POPUP.VOICE_AGENT_CREDENTIALS_JWT_LABEL')
            "
            :placeholder="
              $t(
                'INBOX_MGMT.SETTINGS_POPUP.VOICE_AGENT_CREDENTIALS_JWT_PLACEHOLDER'
              )
            "
          />
          <Input
            v-model="agentCredentials[agent.id].webrtcPassword"
            type="password"
            :label="
              $t('INBOX_MGMT.SETTINGS_POPUP.VOICE_AGENT_CREDENTIALS_PASSWORD_LABEL')
            "
            :placeholder="
              $t(
                'INBOX_MGMT.SETTINGS_POPUP.VOICE_AGENT_CREDENTIALS_PASSWORD_PLACEHOLDER'
              )
            "
          />
          <p
            v-if="agentCredentials[agent.id].hasWebrtcJwt"
            class="text-xs text-n-slate-11 mb-0"
          >
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.VOICE_AGENT_CREDENTIALS_TOKEN_SET') }}
          </p>
          <p
            v-if="agentCredentials[agent.id].hasWebrtcPassword"
            class="text-xs text-n-slate-11 mb-0"
          >
            {{
              $t(
                'INBOX_MGMT.SETTINGS_POPUP.VOICE_AGENT_CREDENTIALS_PASSWORD_SET'
              )
            }}
          </p>
        </div>
        <div>
          <NextButton
            :label="$t('INBOX_MGMT.SETTINGS_POPUP.VOICE_AGENT_CREDENTIALS_SAVE')"
            :is-loading="isCredentialsUpdating"
            @click="updateVoiceAgentCredentials"
          />
        </div>
      </div>
    </SettingsSection>

    <SettingsSection
      :title="$t('INBOX_MGMT.SETTINGS_POPUP.AGENT_ASSIGNMENT')"
      :sub-title="$t('INBOX_MGMT.SETTINGS_POPUP.AGENT_ASSIGNMENT_SUB_TEXT')"
    >
      <!-- New UI for assignment_v2 -->
      <template v-if="hasAssignmentV2">
        <div class="flex items-start gap-3">
          <Switch
            v-model="enableAutoAssignment"
            class="flex-shrink-0 mt-0.5"
            @change="handleToggleAutoAssignment"
          />
          <div class="flex-grow">
            <label class="text-sm text-n-slate-12 font-medium mb-1">
              {{ $t('INBOX_MGMT.ASSIGNMENT.ENABLE_AUTO_ASSIGNMENT') }}
            </label>
            <p class="text-sm text-n-slate-11">
              {{ $t('INBOX_MGMT.ASSIGNMENT.DESCRIPTION') }}
            </p>
          </div>
        </div>
      </template>
    </SettingsFieldSection>
    <SettingsAccordion
      :title="$t('INBOX_MGMT.SETTINGS_POPUP.AGENT_ASSIGNMENT')"
      class="mt-6"
    >
      <SettingsToggleSection
        v-model="enableAutoAssignment"
        compact
        :header="assignmentHeader"
        :description="assignmentDescription"
        @update:model-value="handleToggleAutoAssignment"
      >
        <template
          v-if="enableAutoAssignment && (isEnterprise || hasAssignmentV2)"
          #editor
        >
          <!-- assignment_v2 UI -->
          <template v-if="hasAssignmentV2">
            <!-- Policy Card - When policy is attached -->
            <div
              v-if="showAdvancedAssignmentUI && assignmentPolicy"
              class="ltr:pr-0 rtl:pl-0 ltr:pl-4 rtl:pr-4 py-4"
            >
              <div class="flex items-start gap-4">
                <div
                  class="flex-shrink-0 size-10 rounded-xl bg-n-slate-3 flex items-center justify-center"
                >
                  <span class="i-lucide-zap text-xl text-n-slate-11" />
                </div>
                <div class="flex-grow">
                  <div
                    class="flex items-start justify-between gap-4 mb-4 ltr:pr-4 rtl:pl-4"
                  >
                    <div class="flex flex-col items-start">
                      <span class="text-heading-3 text-n-slate-12 mb-1">
                        {{ assignmentPolicy.name }}
                      </span>
                      <p class="text-body-main text-n-slate-11">
                        {{ $t('INBOX_MGMT.ASSIGNMENT.POLICY_LABEL') }}
                      </p>
                    </div>
                    <NextButton
                      icon="i-lucide-trash-2"
                      ghost
                      ruby
                      sm
                      @click="confirmDeletePolicy"
                    />
                  </div>

                  <ul class="space-y-2 mb-6">
                    <li class="flex items-center gap-2">
                      <span
                        class="w-1.5 h-1.5 rounded-full bg-n-slate-11 flex-shrink-0"
                      />
                      <span class="text-body-main text-n-slate-12">
                        {{ assignmentOrderLabel }}
                      </span>
                    </li>
                    <li class="flex items-center gap-2">
                      <span
                        class="w-1.5 h-1.5 rounded-full bg-n-slate-11 flex-shrink-0"
                      />
                      <span class="text-body-main text-n-slate-12">
                        {{ assignmentMethodLabel }}
                      </span>
                    </li>
                  </ul>

                  <div class="w-full h-px my-4 bg-n-weak" />

                  <NextButton
                    :label="$t('INBOX_MGMT.ASSIGNMENT.CUSTOMIZE_POLICY')"
                    icon="i-lucide-arrow-right"
                    trailing-icon
                    link
                    class="mb-2"
                    @click="navigateToAssignmentPolicyEdit"
                  />
                </div>
              </div>
            </div>

            <!-- Default Policy - When no custom policy attached but feature enabled -->
            <div
              v-else-if="
                showAdvancedAssignmentUI &&
                !assignmentPolicy &&
                !isLoadingPolicy
              "
            >
              <!-- Default Policy Header -->
              <div class="p-4">
                <div class="flex items-start gap-4">
                  <div
                    class="flex-shrink-0 size-10 rounded-xl bg-n-slate-3 dark:bg-n-slate-4 flex items-center justify-center"
                  >
                    <i class="i-lucide-zap text-xl text-n-slate-11" />
                  </div>
                  <div class="flex-grow">
                    <h4 class="text-heading-3 text-n-slate-12 mb-0.5">
                      {{ $t('INBOX_MGMT.ASSIGNMENT.DEFAULT_POLICY_LINKED') }}
                    </h4>
                    <p class="text-body-main text-n-slate-11">
                      {{
                        $t('INBOX_MGMT.ASSIGNMENT.DEFAULT_POLICY_DESCRIPTION')
                      }}
                    </p>
                  </div>
                </div>

                <!-- Action Buttons -->
                <div class="mt-5 flex items-center gap-3">
                  <div
                    v-if="!isLoadingPolicies && availablePolicies.length > 0"
                    v-on-click-outside="closePolicyDropdown"
                    class="relative"
                  >
                    <NextButton
                      icon="i-lucide-link"
                      sm
                      @click="togglePolicyDropdown"
                    >
                      {{ $t('INBOX_MGMT.ASSIGNMENT.LINK_EXISTING_POLICY') }}
                      <Icon
                        icon="i-lucide-chevron-down"
                        class="transition-transform flex-shrink-0"
                        :class="{ 'rotate-180': showPolicyDropdown }"
                      />
                    </NextButton>

                    <DropdownMenu
                      v-if="showPolicyDropdown"
                      class="top-full ltr:left-0 rtl:right-0 mt-2 max-w-64 max-h-72 overflow-y-auto"
                      :menu-items="policyMenuItems"
                      :is-searching="isLoadingPolicies"
                      @action="handlePolicyMenuAction"
                    />
                  </div>

                  <NextButton
                    icon="i-lucide-plus"
                    :label="$t('INBOX_MGMT.ASSIGNMENT.CREATE_NEW_POLICY')"
                    slate
                    faded
                    sm
                    @click="navigateToCreatePolicy"
                  />
                </div>
              </div>

              <!-- Default Rules Info -->
              <div
                class="px-4 py-4 border-t border-n-weak bg-n-slate-2 rounded-b-xl"
              >
                <div class="flex items-start gap-3">
                  <Icon icon="i-lucide-info" class="mt-0.5 text-n-slate-11" />
                  <div>
                    <p class="text-body-main text-n-slate-11 mb-2">
                      {{ $t('INBOX_MGMT.ASSIGNMENT.CURRENT_BEHAVIOR') }}
                    </p>
                    <ul class="space-y-1">
                      <li class="flex items-center gap-2">
                        <span
                          class="w-1 h-1 rounded-full bg-n-slate-10 flex-shrink-0"
                        />
                        <span class="text-body-main text-n-slate-11">
                          {{ $t('INBOX_MGMT.ASSIGNMENT.DEFAULT_RULE_1') }}
                        </span>
                      </li>
                      <li class="flex items-center gap-2">
                        <span
                          class="w-1 h-1 rounded-full bg-n-slate-10 flex-shrink-0"
                        />
                        <span class="text-body-main text-n-slate-11">
                          {{ $t('INBOX_MGMT.ASSIGNMENT.DEFAULT_RULE_2') }}
                        </span>
                      </li>
                    </ul>
                  </div>
                </div>
              </div>
            </div>

            <!-- Default Rules Card - Feature not enabled (no advanced_assignment) -->
            <div
              v-else-if="!showAdvancedAssignmentUI"
              class="ltr:pr-0 rtl:pl-0 ltr:pl-4 rtl:pr-4 py-4"
            >
              <div class="flex items-start gap-4">
                <div
                  class="flex-shrink-0 size-10 rounded-xl bg-n-slate-3 dark:bg-n-slate-4 flex items-center justify-center"
                >
                  <Icon icon="i-lucide-zap" class="text-xl text-n-slate-11" />
                </div>
                <div class="flex-grow">
                  <h4 class="text-heading-3 text-n-slate-12 mb-0.5">
                    {{ $t('INBOX_MGMT.ASSIGNMENT.DEFAULT_RULES_TITLE') }}
                  </h4>
                  <p class="text-body-main text-n-slate-11 mb-4">
                    {{ $t('INBOX_MGMT.ASSIGNMENT.DEFAULT_RULES_DESCRIPTION') }}
                  </p>

                  <ul class="space-y-2 mb-6">
                    <li class="flex items-center gap-2">
                      <span
                        class="w-1.5 h-1.5 rounded-full bg-n-slate-11 flex-shrink-0"
                      />
                      <span class="text-body-main text-n-slate-12">
                        {{ $t('INBOX_MGMT.ASSIGNMENT.DEFAULT_RULE_1') }}
                      </span>
                    </li>
                    <li class="flex items-center gap-2">
                      <span
                        class="w-1.5 h-1.5 rounded-full bg-n-slate-11 flex-shrink-0"
                      />
                      <span class="text-body-main text-n-slate-12">
                        {{ $t('INBOX_MGMT.ASSIGNMENT.DEFAULT_RULE_2') }}
                      </span>
                    </li>
                  </ul>

                  <div class="w-full h-px bg-n-weak my-4" />

                  <!-- Upgrade prompt when advanced_assignment is not enabled -->
                  <div v-if="!hasAdvancedAssignment">
                    <p class="text-body-main text-n-slate-11 mb-1">
                      {{ $t('INBOX_MGMT.ASSIGNMENT.UPGRADE_PROMPT') }}
                    </p>
                    <NextButton
                      :label="$t('INBOX_MGMT.ASSIGNMENT.UPGRADE_TO_BUSINESS')"
                      icon="i-lucide-arrow-right"
                      trailing-icon
                      link
                      @click="navigateToBilling"
                    />
                  </div>
                </div>
              </div>
            </div>
          </template>

          <!-- Old UI for non-assignment_v2 -->
          <template v-else-if="isEnterprise">
            <div class="p-4">
              <woot-input
                v-model="maxAssignmentLimit"
                type="number"
                :class="{ error: v$.maxAssignmentLimit.$error }"
                :error="maxAssignmentLimitErrors"
                :label="$t('INBOX_MGMT.AUTO_ASSIGNMENT.MAX_ASSIGNMENT_LIMIT')"
                class="[&>input]:!mb-0"
                @blur="v$.maxAssignmentLimit.$touch"
              />

              <p class="mt-1.5 text-label-small text-n-slate-11">
                {{
                  $t('INBOX_MGMT.AUTO_ASSIGNMENT.MAX_ASSIGNMENT_LIMIT_SUB_TEXT')
                }}
              </p>

              <div class="flex justify-end mt-4">
                <NextButton
                  :label="$t('INBOX_MGMT.SETTINGS_POPUP.UPDATE')"
                  :disabled="v$.maxAssignmentLimit.$invalid"
                  @click="updateInbox"
                />
              </div>
            </div>
          </template>
        </template>
      </SettingsToggleSection>
    </SettingsAccordion>

    <woot-modal
      v-if="showDeleteConfirmModal"
      :show="showDeleteConfirmModal"
      :on-close="cancelDeletePolicy"
    >
      <div class="p-6">
        <h3 class="text-lg font-medium text-n-slate-12 mb-4">
          {{ $t('INBOX_MGMT.ASSIGNMENT_POLICY.DELETE_CONFIRM_TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11 mb-6 ml-13">
          {{ $t('INBOX_MGMT.ASSIGNMENT_POLICY.DELETE_CONFIRM_MESSAGE') }}
        </p>
        <div class="flex justify-end gap-2">
          <NextButton
            color="slate"
            :label="$t('INBOX_MGMT.ASSIGNMENT_POLICY.CANCEL')"
            @click="cancelDeletePolicy"
          />
          <NextButton
            color="ruby"
            :label="$t('INBOX_MGMT.ASSIGNMENT_POLICY.CONFIRM_DELETE')"
            :is-loading="isDeletingPolicy"
            @click="deleteAssignmentPolicy"
          />
        </div>
      </div>
    </woot-modal>
  </div>
</template>
