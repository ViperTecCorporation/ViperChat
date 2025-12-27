<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { minValue } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { useConfig } from 'dashboard/composables/useConfig';
import SettingsSection from '../../../../../components/SettingsSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';

export default {
  components: {
    SettingsSection,
    NextButton,
    Input,
  },
  props: {
    inbox: {
      type: Object,
      default: () => ({}),
    },
  },
  setup() {
    const { isEnterprise } = useConfig();

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
          hasWebrtcJwt: !!member.has_webrtc_jwt,
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
            hasWebrtcJwt: false,
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
          ({ user_id: userId, webrtc_username: username, webrtc_jwt: jwt }) => {
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
</script>

<template>
  <div>
    <SettingsSection
      :title="$t('INBOX_MGMT.SETTINGS_POPUP.INBOX_AGENTS')"
      :sub-title="$t('INBOX_MGMT.SETTINGS_POPUP.INBOX_AGENTS_SUB_TEXT')"
    >
      <multiselect
        v-model="selectedAgents"
        :options="agentList"
        track-by="id"
        label="name"
        multiple
        :close-on-select="false"
        :clear-on-select="false"
        hide-selected
        placeholder="Pick some"
        selected-label
        :select-label="$t('FORMS.MULTISELECT.ENTER_TO_SELECT')"
        :deselect-label="$t('FORMS.MULTISELECT.ENTER_TO_REMOVE')"
        @select="v$.selectedAgents.$touch"
      />

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
          <p
            v-if="agentCredentials[agent.id].hasWebrtcJwt"
            class="text-xs text-n-slate-11 mb-0"
          >
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.VOICE_AGENT_CREDENTIALS_TOKEN_SET') }}
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
      <label class="w-3/4 settings-item">
        <div class="flex items-center gap-2">
          <input
            id="enableAutoAssignment"
            v-model="enableAutoAssignment"
            type="checkbox"
            @change="handleEnableAutoAssignment"
          />
          <label for="enableAutoAssignment">
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.AUTO_ASSIGNMENT') }}
          </label>
        </div>

        <p class="pb-1 text-sm not-italic text-n-slate-11">
          {{ $t('INBOX_MGMT.SETTINGS_POPUP.AUTO_ASSIGNMENT_SUB_TEXT') }}
        </p>
      </label>

      <div v-if="enableAutoAssignment && isEnterprise" class="py-3">
        <woot-input
          v-model="maxAssignmentLimit"
          type="number"
          :class="{ error: v$.maxAssignmentLimit.$error }"
          :error="maxAssignmentLimitErrors"
          :label="$t('INBOX_MGMT.AUTO_ASSIGNMENT.MAX_ASSIGNMENT_LIMIT')"
          @blur="v$.maxAssignmentLimit.$touch"
        />

        <p class="pb-1 text-sm not-italic text-n-slate-11">
          {{ $t('INBOX_MGMT.AUTO_ASSIGNMENT.MAX_ASSIGNMENT_LIMIT_SUB_TEXT') }}
        </p>

        <NextButton
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.UPDATE')"
          :disabled="v$.maxAssignmentLimit.$invalid"
          @click="updateInbox"
        />
      </div>
    </SettingsSection>
  </div>
</template>
