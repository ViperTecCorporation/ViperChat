<script type="module">
import { io } from 'socket.io-client';
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import inboxMixin from 'shared/mixins/inboxMixin';
import { required } from '@vuelidate/validators';
import { mapGetters } from 'vuex';
// import { createConsumer } from '@rails/actioncable';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

export default {
  components: { NextButton, Switch },
  mixins: [inboxMixin],
  props: {
    inbox: {
      type: Object,
      default: () => ({}),
    },
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      apiKey: '',
      url: 'https://unoapi.cloud',
      ignoreGroupMessages: false,
      ignoreNewsletterMessages: true,
      ignoreGroupIndividualReceipts: true,
      groupOnlyDeliveredStatus: true,
      useGroupConversationSchema: false,
      ignoreHistoryMessages: true,
      webhookSendNewMessages: true,
      sendAgentName: true,
      sendTranscribeAudio: true,
      groqApiKey: '',
      readOnReceipt: false,
      readOnReply: true,
      ignoreBroadcastStatuses: true,
      ignoreBroadcastMessages: true,
      ignoreOwnMessages: false,
      ignoreYourselfMessages: false,
      sendConnectionStatus: true,
      markOnlineOnConnect: true,
      notifyFailedMessages: true,
      composingMessage: false,
      sendReactionAsReply: true,
      sendProfilePicture: true,
      connect: false,
      disconnect: false,
      qrcode: '',
      notice: '',
    };
  },
  computed: {
    ...mapGetters({ uiFlags: 'inboxes/getUIFlags' }),
  },
  validations: {
    apiKey: { required },
    ignoreGroupMessages: { required },
    ignoreNewsletterMessages: { required },
    ignoreGroupIndividualReceipts: { required },
    groupOnlyDeliveredStatus: { required },
    useGroupConversationSchema: { required },
    ignoreHistoryMessages: { required },
    webhookSendNewMessages: { required },
    sendAgentName: { required },
    sendTranscribeAudio: { required },
    groqApiKey: { required },
    readOnReceipt: { required },
    readOnReply: { required },
    url: { required },
    ignoreBroadcastStatuses: { required },
    ignoreBroadcastMessages: { required },
    ignoreOwnMessages: { required },
    ignoreYourselfMessages: { required },
    sendConnectionStatus: { required },
    markOnlineOnConnect: { required },
    notifyFailedMessages: { required },
    composingMessage: { required },
    sendReactionAsReply: { required },
    sendProfilePicture: { required },
  },
  watch: {
    inbox() {
      this.setDefaults();
    },
  },
  mounted() {
    this.setDefaults();
    this.listenerQrCode();
  },
  methods: {
    setDefaults() {
      this.apiKey = this.inbox.provider_config.api_key;
      this.url = this.inbox.provider_config.url;
      this.ignoreGroupMessages = this.inbox.provider_config.ignore_group_messages;
      this.ignoreNewsletterMessages =
        this.inbox.provider_config.ignore_newsletter_messages ?? true;
      this.ignoreGroupIndividualReceipts =
        this.inbox.provider_config.ignore_group_individual_receipts ?? true;
      this.groupOnlyDeliveredStatus =
        this.inbox.provider_config.group_only_delivered_status ?? true;
      this.useGroupConversationSchema =
        this.inbox.provider_config.use_group_conversation_schema ?? false;
      this.ignoreHistoryMessages = this.inbox.provider_config.ignore_history_messages;
      this.webhookSendNewMessages = this.inbox.provider_config.webhook_send_new_messages ?? true;
      this.sendAgentName = this.inbox.provider_config.send_agent_name;
      this.sendTranscribeAudio = this.inbox.provider_config.send_transcribe_audio ?? true;
      this.groqApiKey = this.inbox.provider_config.groq_api_key;
      this.readOnReceipt = this.inbox.provider_config.read_on_receipt;
      this.readOnReply = this.inbox.provider_config.read_on_reply;
      this.ignoreBroadcastStatuses = this.inbox.provider_config.ignore_broadcast_statuses;
      this.ignoreBroadcastMessages = this.inbox.provider_config.ignore_broadcast_messages;
      this.ignoreOwnMessages = this.inbox.provider_config.ignore_own_messages;
      this.ignoreYourselfMessages = this.inbox.provider_config.ignore_yourself_messages;
      this.sendConnectionStatus = this.inbox.provider_config.send_connection_status;
      this.markOnlineOnConnect = this.inbox.provider_config.mark_online_on_connect ?? true;
      this.notifyFailedMessages = this.inbox.provider_config.notify_failed_messages;
      this.composingMessage = this.inbox.provider_config.composing_message;
      this.sendReactionAsReply = this.inbox.provider_config.send_reaction_as_reply;
      this.sendProfilePicture = this.inbox.provider_config.send_profile_picture;
      this.connect = false;
      this.disconnect = false;
    },
    listenerQrCode() {
      const url = `${this.inbox.provider_config.url}`
        .replace('https', 'wss')
        .replace('http', 'ws');
      const socket = io(url, { path: '/ws' });
      socket.on('broadcast', data => {
        console.log('data', data)
        if (data.phone !== this.inbox.provider_config.phone_number_id) {
          this.notice = `Received message from ${data.phone} but the current number in chatwoot is ${this.inbox.provider_config.phone_number_id}`;
          this.qrcode = '';
          // broadcast phone is other
          return;
        }
        if (data.type === 'status') {
          this.notice = data.content;
          this.qrcode = '';
        } else if (data.type === 'qrcode') {
          this.qrcode = data.content;
          this.notice = '';
        }
      });
      // const url = `${this.inbox.provider_config.url}/ws`;
      // const cable = createConsumer(url);
      // cable.subscriptions.create(
      //   {
      //     channel: 'broadcast',
      //     phone_number: this.inbox.provider_config.phone_number_id,
      //   },
      //   {
      //     broadcast: data => {
      //       console.log('broadcast');
      //       this.qrcode = data;
      //     },
      //     connected: () => {
      //       console.log('connected');
      //       this.qrcode = 'waiting for qrcode';
      //     },
      //   }
      // );
    },
    generateToken() {
      const characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
      let token = '';
      for (let i = 0; i < 64; i++) {
        token += characters.charAt(Math.floor(Math.random() * characters.length));
      }

      if (this.apiKey) {
        if (confirm('A token already exists. Do you want to replace it?')) {
          this.apiKey = token;
        }
      } else {
        this.apiKey = token;
      }
    },
    async updateInbox() {
      try {
        const providerConfig = {
          ...(this.inbox.provider_config || {}),
        };

        delete providerConfig.wavoip_token;
        delete providerConfig.reject_calls;
        delete providerConfig.message_calls_webhook;

        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            provider_config: {
              ...providerConfig,
              api_key: this.apiKey,
              ignore_newsletter_messages: this.ignoreNewsletterMessages,
              ignore_group_individual_receipts: this.ignoreGroupIndividualReceipts,
              group_only_delivered_status: this.groupOnlyDeliveredStatus,
              use_group_conversation_schema: this.useGroupConversationSchema,
              ignore_history_messages: this.ignoreHistoryMessages,
              ignore_group_messages: this.ignoreGroupMessages,
              webhook_send_new_messages: this.webhookSendNewMessages,
              send_agent_name: this.sendAgentName,
              send_transcribe_audio: this.sendTranscribeAudio,
              groq_api_key: this.groqApiKey,
              url: this.url,
              read_on_receipt: this.readOnReceipt,
              read_on_reply: this.readOnReply,
              ignore_broadcast_statuses: this.ignoreBroadcastStatuses,
              ignore_broadcast_messages: this.ignoreBroadcastMessages,
              ignore_own_messages: this.ignoreOwnMessages,
              ignore_yourself_messages: this.ignoreYourselfMessages,
              send_connection_status: this.sendConnectionStatus,
              mark_online_on_connect: this.markOnlineOnConnect,
              notify_failed_messages: this.notifyFailedMessages,
              composing_message: this.composingMessage,
              send_reaction_as_reply: this.sendReactionAsReply,
              send_profile_picture: this.sendProfilePicture,
              connect: this.connect,
              disconnect: this.disconnect,
            },
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
  },
};
</script>

<template>
  <div class="my-2 mx-8 text-base">
    <form class="flex flex-col" @submit.prevent="updateInbox()">
      <div class="w-1/4">
        <label :class="{ error: v$.url.$error }">
          <span>
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.URL.LABEL') }}
          </span>
          <input
            v-model.trim="url"
            type="text"
            :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.URL.PLACEHOLDER')"
            @blur="v$.url.$touch"
          />
          <span v-if="v$.url.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.URL.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-1/4">
        <label :class="{ error: v$.apiKey.$error }">
          <span>
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.LABEL') }}
          </span>
          <input
            v-model.trim="apiKey"
            type="text"
            :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.PLACEHOLDER')"
            @blur="v$.apiKey.$touch"
          />
          <span v-if="v$.apiKey.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.ERROR') }}
          </span>
        </label>
      </div>

      <div class="mt-4 mb-2 text-sm font-semibold uppercase tracking-wide text-slate-400">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.SECTIONS.WEBHOOKS') }}
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.webhookSendNewMessages.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="webhookSendNewMessages"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.WEBHOOK_SEND_NEW_MESSAGES.LABEL') }}
          <span v-if="v$.webhookSendNewMessages.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.WEBHOOK_SEND_NEW_MESSAGES.ERROR') }}
          </span>
        </label>
      </div>

      <div class="mt-4 mb-2 text-sm font-semibold uppercase tracking-wide text-slate-400">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.SECTIONS.TRANSCRIPTION') }}
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.sendTranscribeAudio.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="sendTranscribeAudio"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.SEND_TRANSCRIBE_AUDIO.LABEL') }}
          <span v-if="v$.sendTranscribeAudio.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.SEND_TRANSCRIBE_AUDIO.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-full max-w-3xl pb-6">
        <label :class="{ error: v$.groqApiKey.$error }">
          <span>
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.GROQ_API_KEY.LABEL') }}
          </span>
          <input
            v-model.trim="groqApiKey"
            type="text"
            :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.GROQ_API_KEY.PLACEHOLDER')"
            @blur="v$.groqApiKey.$touch"
          />
          <span v-if="v$.groqApiKey.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.GROQ_API_KEY.ERROR') }}
          </span>
        </label>
        <span class="mt-2 block text-sm leading-6 text-slate-500">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.GROQ_API_KEY.SUBTITLE') }}
        </span>
      </div>

      <div class="mt-6 mb-2 text-sm font-semibold uppercase tracking-wide text-slate-400 clear-both">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.SECTIONS.MESSAGING') }}
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.sendAgentName.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="sendAgentName"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.SEND_AGENT_NAME.LABEL') }}
          <span v-if="v$.sendAgentName.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.SEND_AGENT_NAME.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.ignoreGroupMessages.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="ignoreGroupMessages"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.IGNORE_GROUPS.LABEL') }}
          <span v-if="v$.ignoreGroupMessages.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.IGNORE_GROUPS.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.ignoreNewsletterMessages.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="ignoreNewsletterMessages"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.IGNORE_NEWSLETTER_MESSAGES.LABEL') }}
          <span v-if="v$.ignoreNewsletterMessages.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.IGNORE_NEWSLETTER_MESSAGES.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.ignoreGroupIndividualReceipts.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="ignoreGroupIndividualReceipts"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.IGNORE_GROUP_INDIVIDUAL_RECEIPTS.LABEL') }}
          <span v-if="v$.ignoreGroupIndividualReceipts.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.IGNORE_GROUP_INDIVIDUAL_RECEIPTS.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.groupOnlyDeliveredStatus.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="groupOnlyDeliveredStatus"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.GROUP_ONLY_DELIVERED_STATUS.LABEL') }}
          <span v-if="v$.groupOnlyDeliveredStatus.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.GROUP_ONLY_DELIVERED_STATUS.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.useGroupConversationSchema.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="useGroupConversationSchema"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          <span>
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.USE_GROUP_CONVERSATION_SCHEMA.LABEL') }}
            <span class="mt-1 block text-xs leading-5 text-slate-500">
              {{ $t('INBOX_MGMT.ADD.WHATSAPP.USE_GROUP_CONVERSATION_SCHEMA.HELP') }}
            </span>
          </span>
          <span v-if="v$.useGroupConversationSchema.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.USE_GROUP_CONVERSATION_SCHEMA.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.ignoreHistoryMessages.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="ignoreHistoryMessages"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.IGNORE_HISTORY.LABEL') }}
          <span v-if="v$.ignoreHistoryMessages.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.IGNORE_HISTORY.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.readOnReceipt.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="readOnReceipt"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.READ_ON_RECEIPT.LABEL') }}
          <span v-if="v$.readOnReceipt.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.READ_ON_RECEIPT.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.readOnReply.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="readOnReply"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.READ_ON_REPLY.LABEL') }}
          <span v-if="v$.readOnReply.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.READ_ON_REPLY.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.ignoreBroadcastStatuses.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="ignoreBroadcastStatuses"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.IGNORE_BROADCAST_STATUSES.LABEL') }}
          <span v-if="v$.ignoreBroadcastStatuses.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.IGNORE_BROADCAST_STATUSES.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.ignoreBroadcastMessages.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="ignoreBroadcastMessages"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.IGNORE_BROADCAST_MESSAGES.LABEL') }}
          <span v-if="v$.ignoreBroadcastMessages.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.IGNORE_BROADCAST_MESSAGES.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.ignoreOwnMessages.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="ignoreOwnMessages"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.IGNORE_OWN_MESSAGES.LABEL') }}
          <span v-if="v$.ignoreOwnMessages.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.IGNORE_OWN_MESSAGES.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.ignoreYourselfMessages.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="ignoreYourselfMessages"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.IGNORE_YOURSELF_MESSAGES.LABEL') }}
          <span v-if="v$.ignoreYourselfMessages.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.IGNORE_YOURSELF_MESSAGES.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.sendConnectionStatus.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="sendConnectionStatus"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.SEND_CONNECTION_STATUS.LABEL') }}
          <span v-if="v$.sendConnectionStatus.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.SEND_CONNECTION_STATUS.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.markOnlineOnConnect.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="markOnlineOnConnect"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.MARK_ONLINE_ON_CONNECT.LABEL') }}
          <span v-if="v$.markOnlineOnConnect.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.MARK_ONLINE_ON_CONNECT.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.notifyFailedMessages.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="notifyFailedMessages"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.NOTIFY_FAILED_MESSAGES.LABEL') }}
          <span v-if="v$.notifyFailedMessages.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.NOTIFY_FAILED_MESSAGES.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.composingMessage.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="composingMessage"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.COMPOSING_MESSAGE.LABEL') }}
          <span v-if="v$.composingMessage.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.COMPOSING_MESSAGE.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.sendReactionAsReply.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="sendReactionAsReply"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.SEND_REACTION_AS_REPLY.LABEL') }}
          <span v-if="v$.sendReactionAsReply.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.SEND_REACTION_AS_REPLY.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <label :class="{ error: v$.sendProfilePicture.$error }" style="display: flex; align-items: center;">
          <Switch
            v-model="sendProfilePicture"
            style="flex: 0 0 auto; margin-right: 10px;"
          />
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.SEND_PROFILE_PICTURE.LABEL') }}
          <span v-if="v$.sendProfilePicture.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.SEND_PROFILE_PICTURE.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-3/4 pb-4 config-helptext">
        <img v-if="qrcode" :src="qrcode" />
        <div v-if="notice">{{ notice }}</div>
      </div>

      <div class="my-4 w-auto">
        <NextButton
          :is-loading="uiFlags.isCreating"
          solid
          blue
          :label="$t('INBOX_MGMT.ADD.WHATSAPP.WHATSAPP_UPDATE_AND_CONNECT.LABEL')"
          @click="connect = true"
        />
        <NextButton
          :is-loading="uiFlags.isCreating"
          solid
          blue
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_DISCONNECT')"
          @click="disconnect = true"
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
  </div>
</template>

<style lang="scss" scoped>
.whatsapp-settings--content {
  ::v-deep input {
    margin-bottom: 0;
  }
}

.switch {
  flex: 0 0 auto;
  margin-right: 10px;
}

.switch-label {
  display: flex;
  align-items: center;
}

.flex-shrink div .messagingServiceHelptext{
 width:343px;
 max-width:343px;
 margin-bottom:8px;
}

.flex-shrink div .w-1\/4{
 min-width:700px;
 height:77px;
}

#app .flex .w-full{
 transform:translatex(0px) translatey(0px);
}

/* Config helptext */
#app .flex-grow-0 .overflow-hidden .justify-between .flex-shrink div .text-base .flex-col .config-helptext{
 width:100% !important;
}

.flex-shrink div .config-helptext{
 min-height:2px;
 height:30px;
}

.flex-shrink .messagingServiceHelptext label{
 width:204%;
 transform:translatex(0px) translatey(0px);
 position:relative;
 top:6px;
}

.flex-shrink .config-helptext div{
 margin-top:10px;
}

.flex-shrink div img{
 transform:translatex(407px) translatey(-347px);
 width:300px;
 height:300px;
}

.flex-shrink div .message{
 margin-top:-20px;
 font-size:11px;
}
</style>
