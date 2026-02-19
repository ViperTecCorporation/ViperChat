<script>
import { useAlert } from 'dashboard/composables';
import inboxMixin from 'shared/mixins/inboxMixin';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import ImapSettings from '../ImapSettings.vue';
import SmtpSettings from '../SmtpSettings.vue';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import NextButton from 'dashboard/components-next/button/Button.vue';
import TextArea from 'next/textarea/TextArea.vue';
import WhatsappReauthorize from '../channels/whatsapp/Reauthorize.vue';
import { sanitizeAllowedDomains } from 'dashboard/helper/URLHelper';
import Input from 'dashboard/components-next/input/Input.vue';

export default {
  components: {
    SettingsFieldSection,
    ImapSettings,
    SmtpSettings,
    NextButton,
    TextArea,
    WhatsappReauthorize,
    Input,
  },
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
      hmacMandatory: false,
      whatsAppInboxAPIKey: '',
      isRequestingReauthorization: false,
      isSyncingTemplates: false,
      allowedDomains: '',
      isUpdatingAllowedDomains: false,
      isUpdatingVoiceConfig: false,
      customVoiceConfig: {
        webrtcWsUrl: '',
        sipDomain: '',
        sipOutboundProxy: '',
        sipTransport: 'wss',
        stunServers: '',
        turnUrl: '',
        turnUsername: '',
        turnPassword: '',
        authType: 'jwt',
        transferMode: 'sip_refer',
        transferApiUrl: '',
        transferApiToken: '',
        useAgentJwt: true,
        jwtIssuer: '',
        jwtAudience: '',
        jwtSecret: '',
        jwtTtl: '3600',
      },
    };
  },
  validations: {
    whatsAppInboxAPIKey: { required },
  },
  computed: {
    isEmbeddedSignupWhatsApp() {
      return this.inbox.provider_config?.source === 'embedded_signup';
    },
    whatsappAppId() {
      return window.chatwootConfig?.whatsappAppId;
    },
    isForwardingEnabled() {
      return !!this.inbox.forwarding_enabled;
    },
    isCustomVoiceChannel() {
      return this.isAVoiceChannel && this.inbox.provider === 'custom';
    },
  },
  watch: {
    inbox() {
      this.setDefaults();
    },
  },
  mounted() {
    this.setDefaults();
  },
  methods: {
    setDefaults() {
      this.hmacMandatory = this.inbox.hmac_mandatory || false;
      this.allowedDomains = this.inbox.allowed_domains || '';
      if (this.isCustomVoiceChannel) {
        const config = this.inbox.provider_config || {};
        this.customVoiceConfig = {
          webrtcWsUrl: config.webrtc_ws_url || '',
          sipDomain: config.sip_domain || '',
          sipOutboundProxy: config.sip_outbound_proxy || '',
          sipTransport: config.sip_transport || 'wss',
          stunServers: (config.stun_servers || []).join('\n'),
          turnUrl: (config.turn_servers || [])[0]?.urls || '',
          turnUsername: (config.turn_servers || [])[0]?.username || '',
          turnPassword: (config.turn_servers || [])[0]?.credential || '',
          authType: config.auth_type || 'jwt',
          transferMode: config.transfer_mode || 'sip_refer',
          transferApiUrl: config.transfer_api_url || '',
          transferApiToken: '',
          useAgentJwt: config.use_agent_jwt !== false,
          jwtIssuer: config.jwt_issuer || '',
          jwtAudience: config.jwt_audience || '',
          jwtSecret: '',
          jwtTtl: config.jwt_ttl ? config.jwt_ttl.toString() : '3600',
        };
      }
    },
    handleHmacFlag() {
      this.updateInbox();
    },
    async updateInbox() {
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            hmac_mandatory: this.hmacMandatory,
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
    async updateAllowedDomains() {
      this.isUpdatingAllowedDomains = true;
      const sanitizedAllowedDomains = sanitizeAllowedDomains(
        this.allowedDomains
      );
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            allowed_domains: sanitizedAllowedDomains,
          },
        };
        await this.$store.dispatch('inboxes/updateInbox', payload);
        this.allowedDomains = sanitizedAllowedDomains;
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      } finally {
        this.isUpdatingAllowedDomains = false;
      }
    },
    async updateVoiceConfig() {
      this.isUpdatingVoiceConfig = true;
      try {
        const config = {
          webrtc_ws_url: this.customVoiceConfig.webrtcWsUrl,
          sip_domain: this.customVoiceConfig.sipDomain,
          sip_outbound_proxy: this.customVoiceConfig.sipOutboundProxy,
          sip_transport: this.customVoiceConfig.sipTransport,
          stun_servers: this.customVoiceConfig.stunServers
            .split('\n')
            .map(item => item.trim())
            .filter(item => item),
          auth_type: this.customVoiceConfig.authType,
          transfer_mode: this.customVoiceConfig.transferMode,
          transfer_api_url:
            this.customVoiceConfig.transferMode === 'ari'
              ? this.customVoiceConfig.transferApiUrl
              : '',
          transfer_api_token:
            this.customVoiceConfig.transferMode === 'ari'
              ? this.customVoiceConfig.transferApiToken
              : '',
        };
        if (this.customVoiceConfig.turnUrl) {
          config.turn_servers = [
            {
              urls: this.customVoiceConfig.turnUrl.trim(),
              username: this.customVoiceConfig.turnUsername || undefined,
              credential: this.customVoiceConfig.turnPassword || undefined,
            },
          ].filter(server => server.urls);
        }
        if (Array.isArray(config.stun_servers) && !config.stun_servers.length) {
          delete config.stun_servers;
        }
        if (Array.isArray(config.turn_servers) && !config.turn_servers.length) {
          delete config.turn_servers;
        }

        if (this.customVoiceConfig.authType === 'jwt') {
          config.use_agent_jwt = this.customVoiceConfig.useAgentJwt;
          config.jwt_issuer = this.customVoiceConfig.useAgentJwt
            ? ''
            : this.customVoiceConfig.jwtIssuer;
          config.jwt_audience = this.customVoiceConfig.useAgentJwt
            ? ''
            : this.customVoiceConfig.jwtAudience;
          config.jwt_secret = this.customVoiceConfig.useAgentJwt
            ? ''
            : this.customVoiceConfig.jwtSecret;
          config.jwt_ttl = this.customVoiceConfig.useAgentJwt
            ? ''
            : this.customVoiceConfig.jwtTtl;
        }

        const providerConfig = Object.fromEntries(
          Object.entries(config).filter(([, value]) => value !== '')
        );

        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {
            provider_config: providerConfig,
          },
        };

        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      } finally {
        this.isUpdatingVoiceConfig = false;
      }
    },
    async updateWhatsAppInboxAPIKey() {
      try {
        const payload = {
          id: this.inbox.id,
          formData: false,
          channel: {},
        };

        payload.channel.provider_config = {
          ...this.inbox.provider_config,
          api_key: this.whatsAppInboxAPIKey,
        };

        await this.$store.dispatch('inboxes/updateInbox', payload);
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      }
    },
    async handleReconfigure() {
      if (this.$refs.whatsappReauth) {
        await this.$refs.whatsappReauth.requestAuthorization();
      }
    },
    async syncTemplates() {
      this.isSyncingTemplates = true;
      try {
        await this.$store.dispatch('inboxes/syncTemplates', this.inbox.id);
        useAlert(
          this.$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_SUCCESS')
        );
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      } finally {
        this.isSyncingTemplates = false;
      }
    },
  },
};
</script>

<template>
  <div v-if="isATwilioChannel" class="mx-6">
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.ADD.TWILIO.API_CALLBACK.TITLE')"
      :help-text="$t('INBOX_MGMT.ADD.TWILIO.API_CALLBACK.SUBTITLE')"
    >
      <woot-code :script="inbox.callback_webhook_url" lang="html" />
    </SettingsFieldSection>
    <SettingsFieldSection
      v-if="isATwilioWhatsAppChannel"
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_TITLE')"
      :help-text="
        $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_SUBHEADER')
      "
    >
      <NextButton :disabled="isSyncingTemplates" @click="syncTemplates">
        {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_BUTTON') }}
      </NextButton>
    </SettingsFieldSection>
  </div>
  <div v-else-if="isAVoiceChannel" class="mx-8">
    <template v-if="inbox.provider === 'twilio'">
      <SettingsSection
        :title="$t('INBOX_MGMT.ADD.VOICE.CONFIGURATION.TWILIO_VOICE_URL_TITLE')"
        :sub-title="
          $t('INBOX_MGMT.ADD.VOICE.CONFIGURATION.TWILIO_VOICE_URL_SUBTITLE')
        "
      >
        <woot-code :script="inbox.voice_call_webhook_url" lang="html" />
      </SettingsSection>
      <SettingsSection
        :title="
          $t('INBOX_MGMT.ADD.VOICE.CONFIGURATION.TWILIO_STATUS_URL_TITLE')
        "
        :sub-title="
          $t('INBOX_MGMT.ADD.VOICE.CONFIGURATION.TWILIO_STATUS_URL_SUBTITLE')
        "
      >
        <woot-code :script="inbox.voice_status_webhook_url" lang="html" />
      </SettingsSection>
    </template>

    <template v-else-if="isCustomVoiceChannel">
      <SettingsSection
        :title="$t('INBOX_MGMT.ADD.VOICE.PROVIDERS.CUSTOM')"
        :sub-title="$t('INBOX_MGMT.ADD.VOICE.DESC')"
      >
        <div class="flex flex-col gap-4 max-w-3xl">
          <Input
            v-model="customVoiceConfig.webrtcWsUrl"
            :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.WEBRTC_WS_URL.LABEL')"
            :placeholder="
              $t('INBOX_MGMT.ADD.VOICE.CUSTOM.WEBRTC_WS_URL.PLACEHOLDER')
            "
          />
          <Input
            v-model="customVoiceConfig.sipDomain"
            :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_DOMAIN.LABEL')"
            :placeholder="
              $t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_DOMAIN.PLACEHOLDER')
            "
          />
          <Input
            v-model="customVoiceConfig.sipOutboundProxy"
            :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_OUTBOUND_PROXY.LABEL')"
            :placeholder="
              $t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_OUTBOUND_PROXY.PLACEHOLDER')
            "
          />
          <label class="flex flex-col gap-1 text-sm text-n-slate-11">
            {{ $t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_TRANSPORT.LABEL') }}
            <select
              v-model="customVoiceConfig.sipTransport"
              class="rounded-md border-n-strong"
            >
              <option value="wss">
                {{ $t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_TRANSPORT.WSS') }}
              </option>
              <option value="ws">
                {{ $t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_TRANSPORT.WS') }}
              </option>
            </select>
          </label>
          <TextArea
            v-model="customVoiceConfig.stunServers"
            auto-height
            :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.STUN_SERVERS.LABEL')"
            :placeholder="
              $t('INBOX_MGMT.ADD.VOICE.CUSTOM.STUN_SERVERS.PLACEHOLDER')
            "
          />
          <Input
            v-model="customVoiceConfig.turnUrl"
            :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.TURN_URL.LABEL')"
            :placeholder="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.TURN_URL.PLACEHOLDER')"
          />
          <Input
            v-model="customVoiceConfig.turnUsername"
            :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.TURN_USERNAME.LABEL')"
            :placeholder="
              $t('INBOX_MGMT.ADD.VOICE.CUSTOM.TURN_USERNAME.PLACEHOLDER')
            "
          />
          <Input
            v-model="customVoiceConfig.turnPassword"
            type="password"
            :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.TURN_PASSWORD.LABEL')"
            :placeholder="
              $t('INBOX_MGMT.ADD.VOICE.CUSTOM.TURN_PASSWORD.PLACEHOLDER')
            "
          />
          <label class="flex flex-col gap-1 text-sm text-n-slate-11">
            {{ $t('INBOX_MGMT.ADD.VOICE.CUSTOM.AUTH_TYPE.LABEL') }}
            <select
              v-model="customVoiceConfig.authType"
              class="rounded-md border-n-strong"
            >
              <option value="jwt">
                {{ $t('INBOX_MGMT.ADD.VOICE.CUSTOM.AUTH_TYPE.JWT') }}
              </option>
              <option value="password">
                {{ $t('INBOX_MGMT.ADD.VOICE.CUSTOM.AUTH_TYPE.PASSWORD') }}
              </option>
            </select>
          </label>
          <label class="flex flex-col gap-1 text-sm text-n-slate-11">
            {{ $t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_MODE.LABEL') }}
            <select
              v-model="customVoiceConfig.transferMode"
              class="rounded-md border-n-strong"
            >
              <option value="sip_refer">
                {{ $t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_MODE.SIP_REFER') }}
              </option>
              <option value="ari">
                {{ $t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_MODE.ARI') }}
              </option>
            </select>
          </label>
          <template v-if="customVoiceConfig.transferMode === 'ari'">
            <Input
              v-model="customVoiceConfig.transferApiUrl"
              :label="
                $t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_API_URL.LABEL')
              "
              :placeholder="
                $t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_API_URL.PLACEHOLDER')
              "
            />
            <Input
              v-model="customVoiceConfig.transferApiToken"
              type="password"
              :label="
                $t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_API_TOKEN.LABEL')
              "
              :placeholder="
                $t(
                  'INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_API_TOKEN.PLACEHOLDER'
                )
              "
            />
          </template>
          <template v-if="customVoiceConfig.authType === 'jwt'">
            <label class="flex items-center gap-2 text-sm text-n-slate-11">
              <input v-model="customVoiceConfig.useAgentJwt" type="checkbox" />
              {{ $t('INBOX_MGMT.ADD.VOICE.CUSTOM.USE_AGENT_JWT') }}
            </label>
            <template v-if="!customVoiceConfig.useAgentJwt">
              <Input
                v-model="customVoiceConfig.jwtIssuer"
                :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_ISSUER.LABEL')"
                :placeholder="
                  $t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_ISSUER.PLACEHOLDER')
                "
              />
              <Input
                v-model="customVoiceConfig.jwtAudience"
                :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_AUDIENCE.LABEL')"
                :placeholder="
                  $t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_AUDIENCE.PLACEHOLDER')
                "
              />
              <Input
                v-model="customVoiceConfig.jwtSecret"
                type="password"
                :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_SECRET.LABEL')"
                :placeholder="
                  $t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_SECRET.PLACEHOLDER')
                "
              />
              <Input
                v-model="customVoiceConfig.jwtTtl"
                :label="$t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_TTL.LABEL')"
                :placeholder="
                  $t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_TTL.PLACEHOLDER')
                "
              />
            </template>
          </template>
          <div>
            <NextButton
              :label="$t('INBOX_MGMT.SETTINGS_POPUP.UPDATE')"
              :is-loading="isUpdatingVoiceConfig"
              @click="updateVoiceConfig"
            />
          </div>
        </div>
      </SettingsSection>
    </template>
  </div>

  <div v-else-if="isALineChannel" class="mx-6">
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.ADD.LINE_CHANNEL.API_CALLBACK.TITLE')"
      :help-text="$t('INBOX_MGMT.ADD.LINE_CHANNEL.API_CALLBACK.SUBTITLE')"
    >
      <woot-code :script="inbox.callback_webhook_url" lang="html" />
    </SettingsFieldSection>
  </div>
  <div v-else-if="isAWebWidgetInbox">
    <div class="mx-6">
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.SETTINGS_POPUP.ALLOWED_DOMAINS.TITLE')"
        :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.ALLOWED_DOMAINS.SUBTITLE')"
        class="[&>div]:!items-start"
      >
        <woot-code
          :script="inbox.web_widget_script"
          lang="html"
          :codepen-title="`${inbox.name} - ViperChat Widget Test`"
          enable-code-pen
        />
        <template #extra>
          <div class="grid grid-cols-1 lg:grid-cols-8">
            <div class="col-span-1 lg:col-span-2 invisible" />
            <div class="col-span-1 lg:col-span-6 mt-4 justify-self-end">
              <NextButton
                :label="$t('INBOX_MGMT.SETTINGS_POPUP.UPDATE')"
                :is-loading="isUpdatingAllowedDomains"
                @click="updateAllowedDomains"
              />
            </div>
          </div>
        </template>
      </SettingsFieldSection>

      <SettingsFieldSection
        :label="$t('INBOX_MGMT.SETTINGS_POPUP.HMAC_VERIFICATION')"
      >
        <woot-code :script="inbox.hmac_token" />
        <template #extra>
          <div class="grid grid-cols-1 lg:grid-cols-8">
            <div class="col-span-1 lg:col-span-2 invisible" />
            <p
              class="col-span-1 lg:col-span-6 mt-1.5 text-label-small text-n-slate-11 ltr:ml-1 rtl:mr-1"
            >
              {{ $t('INBOX_MGMT.SETTINGS_POPUP.HMAC_DESCRIPTION') }}
              <a
                target="_blank"
                rel="noopener noreferrer"
                href="https://www.chatwoot.com/docs/product/channels/live-chat/sdk/identity-validation/"
                class="text-n-blue-11 hover:underline text-label-small"
              >
                {{ $t('INBOX_MGMT.SETTINGS_POPUP.HMAC_LINK_TO_DOCS') }}
              </a>
            </p>
          </div>
        </template>
      </SettingsFieldSection>
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.SETTINGS_POPUP.HMAC_MANDATORY_VERIFICATION')"
        :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.HMAC_MANDATORY_DESCRIPTION')"
      >
        <div class="flex gap-2 items-center">
          <input
            id="hmacMandatory"
            v-model="hmacMandatory"
            type="checkbox"
            @change="handleHmacFlag"
          />
          <label for="hmacMandatory" class="text-body-main text-n-slate-12">
            {{ $t('INBOX_MGMT.EDIT.ENABLE_HMAC.LABEL') }}
          </label>
        </div>
      </SettingsFieldSection>
    </div>
  </div>
  <div v-else-if="isAPIInbox" class="mx-6">
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.INBOX_IDENTIFIER')"
      :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.INBOX_IDENTIFIER_SUB_TEXT')"
    >
      <woot-code :script="inbox.inbox_identifier" />
    </SettingsFieldSection>

    <SettingsFieldSection
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.HMAC_VERIFICATION')"
      :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.HMAC_DESCRIPTION')"
    >
      <woot-code :script="inbox.hmac_token" />
    </SettingsFieldSection>
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.SETTINGS_POPUP.HMAC_MANDATORY_VERIFICATION')"
      :help-text="$t('INBOX_MGMT.SETTINGS_POPUP.HMAC_MANDATORY_DESCRIPTION')"
    >
      <div class="flex gap-2 items-center">
        <input
          id="hmacMandatory"
          v-model="hmacMandatory"
          type="checkbox"
          @change="handleHmacFlag"
        />
        <label for="hmacMandatory" class="text-body-main text-n-slate-12">
          {{ $t('INBOX_MGMT.EDIT.ENABLE_HMAC.LABEL') }}
        </label>
      </div>
    </SettingsFieldSection>
  </div>
  <div v-else-if="isAnEmailChannel" class="mx-6">
    <div>
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.SETTINGS_POPUP.FORWARD_EMAIL_TITLE')"
        :help-text="
          isForwardingEnabled
            ? $t('INBOX_MGMT.SETTINGS_POPUP.FORWARD_EMAIL_SUB_TEXT')
            : ''
        "
      >
        <woot-code
          v-if="isForwardingEnabled"
          :script="inbox.forward_to_email"
        />
        <div
          v-else
          class="py-2 px-3 bg-n-amber-3 outline-n-amber-4 text-n-amber-11 outline outline-1 -outline-offset-1 rounded-xl"
        >
          <p class="text-body-para mb-0">
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.FORWARD_EMAIL_NOT_CONFIGURED') }}
          </p>
        </div>
      </SettingsFieldSection>
    </div>
    <ImapSettings :inbox="inbox" />
    <SmtpSettings v-if="inbox.imap_enabled" :inbox="inbox" />
  </div>
  <div v-else-if="isAWhatsAppChannel && !isATwilioChannel">
    <div v-if="inbox.provider_config" class="mx-6">
      <!-- Embedded Signup Section -->
      <template v-if="isEmbeddedSignupWhatsApp">
        <SettingsFieldSection
          v-if="whatsappAppId"
          :label="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_EMBEDDED_SIGNUP_TITLE')
          "
          :help-text="`${$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_EMBEDDED_SIGNUP_SUBHEADER')} ${$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_EMBEDDED_SIGNUP_DESCRIPTION')}`"
        >
          <div class="flex flex-col gap-1 items-start">
            <NextButton @click="handleReconfigure">
              {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_RECONFIGURE_BUTTON') }}
            </NextButton>
          </div>
        </SettingsFieldSection>
      </template>

      <!-- Manual Setup Section -->
      <template v-else>
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_WEBHOOK_TITLE')"
          :help-text="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_WEBHOOK_SUBHEADER')
          "
        >
          <woot-code :script="inbox.provider_config.webhook_verify_token" />
        </SettingsFieldSection>
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_TITLE')"
          :help-text="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_SUBHEADER')
          "
        >
          <woot-code :script="inbox.provider_config.api_key" />
        </SettingsFieldSection>
        <SettingsFieldSection
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_TITLE')"
          :help-text="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_SUBHEADER')
          "
        >
          <div
            class="flex flex-1 justify-between items-center whatsapp-settings--content"
          >
            <woot-input
              v-model="whatsAppInboxAPIKey"
              type="text"
              class="flex-1 mr-2 [&>input]:!mb-0"
              :placeholder="
                $t(
                  'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_PLACEHOLDER'
                )
              "
            />
            <NextButton
              :disabled="v$.whatsAppInboxAPIKey.$invalid"
              @click="updateWhatsAppInboxAPIKey"
            >
              {{
                $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_BUTTON')
              }}
            </NextButton>
          </div>
        </SettingsFieldSection>
      </template>
      <SettingsFieldSection
        :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_TITLE')"
        :help-text="
          $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_SUBHEADER')
        "
      >
        <NextButton :disabled="isSyncingTemplates" @click="syncTemplates">
          {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_BUTTON') }}
        </NextButton>
      </SettingsFieldSection>
    </div>
    <WhatsappReauthorize
      v-if="isEmbeddedSignupWhatsApp"
      ref="whatsappReauth"
      :inbox="inbox"
      class="hidden"
    />
  </div>
</template>

<style lang="scss" scoped>
.whatsapp-settings--content {
  ::v-deep input {
    margin-bottom: 0;
  }
}
</style>
