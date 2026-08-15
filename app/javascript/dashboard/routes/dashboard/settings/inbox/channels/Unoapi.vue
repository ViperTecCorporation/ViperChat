<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import {
  integer,
  maxValue,
  minValue,
  required,
  requiredIf,
} from '@vuelidate/validators';
import router from '../../../../index';
import { isPhoneE164OrEmpty } from 'shared/helpers/Validators';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SwitchControl from 'dashboard/components-next/switch/Switch.vue';
import UnoapiSettingLabel from '../settingsPage/UnoapiSettingLabel.vue';

export default {
  components: {
    NextButton,
    SwitchControl,
    UnoapiSettingLabel,
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      inboxName: '',
      phoneNumber: '',
      apiKey: '',
      url: 'https://unoapi.cloud',
      ignoreGroupMessages: false,
      ignoreHistoryMessages: true,
      historyMaxAgeDays: 7,
      sendAgentName: true,
      webhookSendNewMessages: true,
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'inboxes/getUIFlags',
      globalConfig: 'globalConfig/get',
    }),
    apiKeyPlaceholder() {
      return this.globalConfig.unoapiAuthTokenConfigured
        ? this.$t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.GLOBAL_PLACEHOLDER')
        : this.$t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.PLACEHOLDER');
    },
  },
  validations() {
    return {
      inboxName: { required },
      phoneNumber: { required, isPhoneE164OrEmpty },
      apiKey: {
        required: requiredIf(
          () => !this.globalConfig.unoapiAuthTokenConfigured
        ),
      },
      ignoreGroupMessages: { required },
      ignoreHistoryMessages: { required },
      historyMaxAgeDays: {
        required,
        integer,
        minValue: minValue(1),
        maxValue: maxValue(3650),
      },
      sendAgentName: { required },
      webhookSendNewMessages: { required },
      url: { required },
    };
  },
  mounted() {
    this.url = this.globalConfig.unoapiApiUrl || this.url;
  },
  methods: {
    generateToken() {
      const characters =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
      let token = '';
      for (let i = 0; i < 64; i += 1) {
        token += characters.charAt(
          Math.floor(Math.random() * characters.length)
        );
      }

      if (this.apiKey) {
        if (
          // eslint-disable-next-line no-alert
          window.confirm('A token already exists. Do you want to replace it?')
        ) {
          this.apiKey = token;
        }
      } else {
        this.apiKey = token;
      }
    },
    async createChannel() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        return;
      }

      try {
        const whatsappChannel = await this.$store.dispatch(
          'inboxes/createChannel',
          {
            name: this.inboxName,
            channel: {
              type: 'whatsapp',
              contact_sync_enabled: true,
              contact_export_enabled: true,
              phone_number: this.phoneNumber,
              provider: 'unoapi',
              provider_config: {
                api_key: this.apiKey || null,
                phone_number: this.phoneNumber,
                phone_number_id: this.phoneNumber.replace('+', ''),
                business_account_id: this.phoneNumber.replace('+', ''),
                ignore_history_messages: this.ignoreHistoryMessages,
                history_max_age_days: Number(this.historyMaxAgeDays) || 7,
                ignore_group_messages: this.ignoreGroupMessages,
                ignore_newsletter_messages: true,
                ignore_group_individual_receipts: true,
                group_only_delivered_status: true,
                use_group_conversation_schema: true,
                send_agent_name: this.sendAgentName,
                webhook_send_new_messages: this.webhookSendNewMessages,
                send_transcribe_audio: true,
                read_on_receipt: false,
                read_on_reply: true,
                ignore_broadcast_statuses: true,
                ignore_broadcast_messages: true,
                ignore_own_messages: false,
                ignore_yourself_messages: false,
                ignore_external_echo_automations: false,
                send_connection_status: true,
                mark_online_on_connect: false,
                notify_failed_messages: true,
                composing_message: false,
                send_reaction_as_reply: true,
                send_profile_picture: true,
                url:
                  this.url === this.globalConfig.unoapiApiUrl ? null : this.url,
              },
            },
          }
        );

        router.replace({
          name: 'settings_inboxes_add_agents',
          params: {
            page: 'new',
            inbox_id: whatsappChannel.id,
          },
        });
      } catch (error) {
        useAlert(
          this.$t('INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE') +
            '\n detail:' +
            error
        );
      }
    },
  },
};
</script>

<template>
  <form class="mx-0 flex flex-wrap" @submit.prevent="createChannel()">
    <div class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%]">
      <label :class="{ error: v$.inboxName.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.LABEL') }}
        <input
          v-model.trim="inboxName"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.PLACEHOLDER')"
          @blur="v$.inboxName.$touch"
        />
        <span v-if="v$.inboxName.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.ERROR') }}
        </span>
      </label>
    </div>

    <div class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%]">
      <label :class="{ error: v$.phoneNumber.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.LABEL') }}
        <input
          v-model.trim="phoneNumber"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.PLACEHOLDER')"
          @blur="v$.phoneNumber.$touch"
        />
        <span v-if="v$.phoneNumber.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.ERROR') }}
        </span>
      </label>
    </div>

    <div class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%]">
      <label :class="{ error: v$.apiKey.$error }">
        <span>
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.LABEL') }}
        </span>
        <input
          v-model.trim="apiKey"
          type="text"
          :placeholder="apiKeyPlaceholder"
          @blur="v$.apiKey.$touch"
        />
        <span v-if="v$.apiKey.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.ERROR') }}
        </span>
      </label>
    </div>

    <div class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%]">
      <label :class="{ error: v$.url.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.URL.LABEL') }}
        <input
          v-model.trim="url"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.URL.PLACEHOLDER')"
        />
        <span v-if="v$.url.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.URL.ERROR') }}
        </span>
      </label>
    </div>

    <div class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%] config-helptext">
      <label
        :class="{ error: v$.sendAgentName.$error }"
        class="flex items-center"
      >
        <SwitchControl v-model="sendAgentName" class="mr-2.5 shrink-0" />
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.SEND_AGENT_NAME.LABEL') }}
        <span v-if="v$.sendAgentName.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.SEND_AGENT_NAME.ERROR') }}
        </span>
      </label>
    </div>

    <div class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%] config-helptext">
      <label
        :class="{ error: v$.ignoreGroupMessages.$error }"
        class="flex items-center"
      >
        <SwitchControl v-model="ignoreGroupMessages" class="mr-2.5 shrink-0" />
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.IGNORE_GROUPS.LABEL') }}
        <span v-if="v$.ignoreGroupMessages.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.IGNORE_GROUPS.ERROR') }}
        </span>
      </label>
    </div>

    <div class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%] config-helptext">
      <label
        :class="{ error: v$.ignoreHistoryMessages.$error }"
        class="flex items-center"
      >
        <SwitchControl
          v-model="ignoreHistoryMessages"
          class="mr-2.5 shrink-0"
        />
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.IGNORE_HISTORY.LABEL') }}
        <span v-if="v$.ignoreHistoryMessages.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.IGNORE_HISTORY.ERROR') }}
        </span>
      </label>
    </div>

    <div
      v-if="!ignoreHistoryMessages"
      class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%] pl-10"
    >
      <label :class="{ error: v$.historyMaxAgeDays.$error }">
        <UnoapiSettingLabel
          :label="$t('INBOX_MGMT.ADD.WHATSAPP.HISTORY_MAX_AGE_DAYS.LABEL')"
          :help="$t('INBOX_MGMT.ADD.WHATSAPP.HISTORY_MAX_AGE_DAYS.HELP')"
        />
        <input
          v-model.number="historyMaxAgeDays"
          type="number"
          min="1"
          max="3650"
          @blur="v$.historyMaxAgeDays.$touch"
        />
        <span v-if="v$.historyMaxAgeDays.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.HISTORY_MAX_AGE_DAYS.ERROR') }}
        </span>
      </label>
    </div>

    <div class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%] config-helptext">
      <label
        :class="{ error: v$.webhookSendNewMessages.$error }"
        class="flex items-center"
      >
        <SwitchControl
          v-model="webhookSendNewMessages"
          class="mr-2.5 shrink-0"
        />
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.WEBHOOK_SEND_NEW_MESSAGES.LABEL') }}
        <span v-if="v$.webhookSendNewMessages.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.WEBHOOK_SEND_NEW_MESSAGES.ERROR') }}
        </span>
      </label>
    </div>

    <div class="w-full mt-5">
      <NextButton
        :is-loading="uiFlags.isCreating"
        type="submit"
        solid
        blue
        :label="$t('INBOX_MGMT.ADD.WHATSAPP.SUBMIT_BUTTON')"
      />
      <NextButton
        :is-loading="uiFlags.isCreating"
        solid
        blue
        :label="$t('INBOX_MGMT.ADD.WHATSAPP.GENERATE_API_KEY.LABEL')"
        @click="generateToken"
      />
    </div>
  </form>
</template>

<style lang="scss" scoped>
.switch {
  flex: 0 0 auto;
  margin-right: 10px;
}
.switch-label {
  display: flex;
  align-items: center;
}
</style>
