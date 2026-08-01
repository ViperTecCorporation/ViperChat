<script setup>
import { reactive, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { isPhoneE164 } from 'shared/helpers/Validators';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import PageHeader from '../../SettingsSubPageHeader.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const store = useStore();
const router = useRouter();

const state = reactive({
  provider: 'twilio',
  phoneNumber: '',
  accountSid: '',
  authToken: '',
  apiKeySid: '',
  apiKeySecret: '',
  webrtcWsUrl: '',
  sipDomain: '',
  sipOutboundProxy: '',
  sipTransport: 'wss',
  authType: 'jwt',
  transferMode: 'sip_refer',
  transferApiUrl: '',
  transferApiToken: '',
  useAgentJwt: true,
  jwtIssuer: '',
  jwtAudience: '',
  jwtSecret: '',
  jwtTtl: '3600',
});

const uiFlags = useMapGetter('inboxes/getUIFlags');

const isCustomProvider = computed(() => state.provider === 'custom');

const validationRules = computed(() => {
  if (!isCustomProvider.value) {
    return {
      phoneNumber: { required, isPhoneE164 },
      accountSid: { required },
      authToken: { required },
      apiKeySid: { required },
      apiKeySecret: { required },
    };
  }

  return {
    phoneNumber: { required, isPhoneE164 },
    webrtcWsUrl: { required },
    sipDomain: { required },
    transferApiUrl: state.transferMode === 'ari' ? { required } : {},
    jwtSecret:
      state.authType === 'jwt' && !state.useAgentJwt ? { required } : {},
  };
});

const v$ = useVuelidate(validationRules, state);
const isSubmitDisabled = computed(() => v$.value.$invalid);

const formErrors = computed(() => ({
  phoneNumber: v$.value.phoneNumber?.$error
    ? t('INBOX_MGMT.ADD.VOICE.PHONE_NUMBER.ERROR')
    : '',
  accountSid: v$.value.accountSid?.$error
    ? t('INBOX_MGMT.ADD.VOICE.TWILIO.ACCOUNT_SID.REQUIRED')
    : '',
  authToken: v$.value.authToken?.$error
    ? t('INBOX_MGMT.ADD.VOICE.TWILIO.AUTH_TOKEN.REQUIRED')
    : '',
  apiKeySid: v$.value.apiKeySid?.$error
    ? t('INBOX_MGMT.ADD.VOICE.TWILIO.API_KEY_SID.REQUIRED')
    : '',
  apiKeySecret: v$.value.apiKeySecret?.$error
    ? t('INBOX_MGMT.ADD.VOICE.TWILIO.API_KEY_SECRET.REQUIRED')
    : '',
  webrtcWsUrl: v$.value.webrtcWsUrl?.$error
    ? t('INBOX_MGMT.ADD.VOICE.CUSTOM.WEBRTC_WS_URL.REQUIRED')
    : '',
  sipDomain: v$.value.sipDomain?.$error
    ? t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_DOMAIN.REQUIRED')
    : '',
  transferApiUrl: v$.value.transferApiUrl?.$error
    ? t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_API_URL.REQUIRED')
    : '',
  jwtSecret: v$.value.jwtSecret?.$error
    ? t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_SECRET.REQUIRED')
    : '',
}));

function getProviderConfig() {
  if (!isCustomProvider.value) {
    return {
      account_sid: state.accountSid,
      auth_token: state.authToken,
      api_key_sid: state.apiKeySid,
      api_key_secret: state.apiKeySecret,
    };
  }

  const config = {
    webrtc_ws_url: state.webrtcWsUrl,
    sip_domain: state.sipDomain,
    sip_outbound_proxy: state.sipOutboundProxy,
    sip_transport: state.sipTransport,
    auth_type: state.authType,
    transfer_mode: state.transferMode,
    transfer_api_url: state.transferMode === 'ari' ? state.transferApiUrl : '',
    transfer_api_token:
      state.transferMode === 'ari' ? state.transferApiToken : '',
  };

  if (state.authType === 'jwt') {
    config.use_agent_jwt = state.useAgentJwt;
    config.jwt_secret = state.useAgentJwt ? '' : state.jwtSecret;
    config.jwt_issuer = state.useAgentJwt ? '' : state.jwtIssuer;
    config.jwt_audience = state.useAgentJwt ? '' : state.jwtAudience;
    config.jwt_ttl = state.useAgentJwt ? '' : state.jwtTtl;
  }

  return Object.fromEntries(
    Object.entries(config).filter(([, value]) => value !== '')
  );
}

async function createChannel() {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) return;

  try {
    const channel = await store.dispatch('inboxes/createVoiceChannel', {
      name: `Voice (${state.phoneNumber})`,
      voice: {
        phone_number: state.phoneNumber,
        provider: state.provider,
        provider_config: getProviderConfig(),
      },
    });

    router.replace({
      name: 'settings_inboxes_add_agents',
      params: { page: 'new', inbox_id: channel.id },
    });
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        t('INBOX_MGMT.ADD.VOICE.API.ERROR_MESSAGE')
    );
  }
}
</script>

<template>
  <div class="overflow-auto col-span-6 p-6 w-full h-full">
    <PageHeader
      :header-title="t('INBOX_MGMT.ADD.VOICE.TITLE')"
      :header-content="t('INBOX_MGMT.ADD.VOICE.DESC')"
    />

    <form
      class="flex flex-col gap-4 flex-wrap mx-0"
      @submit.prevent="createChannel"
    >
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('INBOX_MGMT.ADD.VOICE.PROVIDERS.LABEL') }}
        <select v-model="state.provider" class="rounded-md border-n-strong">
          <option value="twilio">
            {{ t('INBOX_MGMT.ADD.VOICE.PROVIDERS.TWILIO') }}
          </option>
          <option value="custom">
            {{ t('INBOX_MGMT.ADD.VOICE.PROVIDERS.CUSTOM') }}
          </option>
        </select>
      </label>

      <Input
        v-model="state.phoneNumber"
        :label="t('INBOX_MGMT.ADD.VOICE.PHONE_NUMBER.LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.VOICE.PHONE_NUMBER.PLACEHOLDER')"
        :message="formErrors.phoneNumber"
        :message-type="formErrors.phoneNumber ? 'error' : 'info'"
        @blur="v$.phoneNumber?.$touch"
      />

      <template v-if="!isCustomProvider">
        <Input
          v-model="state.accountSid"
          :label="t('INBOX_MGMT.ADD.VOICE.TWILIO.ACCOUNT_SID.LABEL')"
          :placeholder="
            t('INBOX_MGMT.ADD.VOICE.TWILIO.ACCOUNT_SID.PLACEHOLDER')
          "
          :message="formErrors.accountSid"
          :message-type="formErrors.accountSid ? 'error' : 'info'"
          @blur="v$.accountSid?.$touch"
        />

        <Input
          v-model="state.authToken"
          type="password"
          :label="t('INBOX_MGMT.ADD.VOICE.TWILIO.AUTH_TOKEN.LABEL')"
          :placeholder="t('INBOX_MGMT.ADD.VOICE.TWILIO.AUTH_TOKEN.PLACEHOLDER')"
          :message="formErrors.authToken"
          :message-type="formErrors.authToken ? 'error' : 'info'"
          @blur="v$.authToken?.$touch"
        />

        <Input
          v-model="state.apiKeySid"
          :label="t('INBOX_MGMT.ADD.VOICE.TWILIO.API_KEY_SID.LABEL')"
          :placeholder="
            t('INBOX_MGMT.ADD.VOICE.TWILIO.API_KEY_SID.PLACEHOLDER')
          "
          :message="formErrors.apiKeySid"
          :message-type="formErrors.apiKeySid ? 'error' : 'info'"
          @blur="v$.apiKeySid?.$touch"
        />

        <Input
          v-model="state.apiKeySecret"
          type="password"
          :label="t('INBOX_MGMT.ADD.VOICE.TWILIO.API_KEY_SECRET.LABEL')"
          :placeholder="
            t('INBOX_MGMT.ADD.VOICE.TWILIO.API_KEY_SECRET.PLACEHOLDER')
          "
          :message="formErrors.apiKeySecret"
          :message-type="formErrors.apiKeySecret ? 'error' : 'info'"
          @blur="v$.apiKeySecret?.$touch"
        />
      </template>

      <template v-else>
        <Input
          v-model="state.webrtcWsUrl"
          :label="t('INBOX_MGMT.ADD.VOICE.CUSTOM.WEBRTC_WS_URL.LABEL')"
          :placeholder="
            t('INBOX_MGMT.ADD.VOICE.CUSTOM.WEBRTC_WS_URL.PLACEHOLDER')
          "
          :message="formErrors.webrtcWsUrl"
          :message-type="formErrors.webrtcWsUrl ? 'error' : 'info'"
          @blur="v$.webrtcWsUrl?.$touch"
        />

        <Input
          v-model="state.sipDomain"
          :label="t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_DOMAIN.LABEL')"
          :placeholder="t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_DOMAIN.PLACEHOLDER')"
          :message="formErrors.sipDomain"
          :message-type="formErrors.sipDomain ? 'error' : 'info'"
          @blur="v$.sipDomain?.$touch"
        />

        <Input
          v-model="state.sipOutboundProxy"
          :label="t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_OUTBOUND_PROXY.LABEL')"
          :placeholder="
            t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_OUTBOUND_PROXY.PLACEHOLDER')
          "
        />

        <label class="flex flex-col gap-1 text-sm text-n-slate-11">
          {{ t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_TRANSPORT.LABEL') }}
          <select
            v-model="state.sipTransport"
            class="rounded-md border-n-strong"
          >
            <option value="wss">
              {{ t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_TRANSPORT.WSS') }}
            </option>
            <option value="ws">
              {{ t('INBOX_MGMT.ADD.VOICE.CUSTOM.SIP_TRANSPORT.WS') }}
            </option>
          </select>
        </label>

        <label class="flex flex-col gap-1 text-sm text-n-slate-11">
          {{ t('INBOX_MGMT.ADD.VOICE.CUSTOM.AUTH_TYPE.LABEL') }}
          <select v-model="state.authType" class="rounded-md border-n-strong">
            <option value="jwt">
              {{ t('INBOX_MGMT.ADD.VOICE.CUSTOM.AUTH_TYPE.JWT') }}
            </option>
            <option value="password">
              {{ t('INBOX_MGMT.ADD.VOICE.CUSTOM.AUTH_TYPE.PASSWORD') }}
            </option>
          </select>
        </label>

        <label class="flex flex-col gap-1 text-sm text-n-slate-11">
          {{ t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_MODE.LABEL') }}
          <select
            v-model="state.transferMode"
            class="rounded-md border-n-strong"
          >
            <option value="sip_refer">
              {{ t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_MODE.SIP_REFER') }}
            </option>
            <option value="ari">
              {{ t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_MODE.ARI') }}
            </option>
          </select>
        </label>

        <template v-if="state.transferMode === 'ari'">
          <Input
            v-model="state.transferApiUrl"
            :label="t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_API_URL.LABEL')"
            :placeholder="
              t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_API_URL.PLACEHOLDER')
            "
            :message="formErrors.transferApiUrl"
            :message-type="formErrors.transferApiUrl ? 'error' : 'info'"
            @blur="v$.transferApiUrl?.$touch"
          />

          <Input
            v-model="state.transferApiToken"
            type="password"
            :label="t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_API_TOKEN.LABEL')"
            :placeholder="
              t('INBOX_MGMT.ADD.VOICE.CUSTOM.TRANSFER_API_TOKEN.PLACEHOLDER')
            "
          />
        </template>

        <template v-if="state.authType === 'jwt'">
          <label class="flex items-center gap-2 text-sm text-n-slate-11">
            <input v-model="state.useAgentJwt" type="checkbox" />
            {{ t('INBOX_MGMT.ADD.VOICE.CUSTOM.USE_AGENT_JWT') }}
          </label>

          <template v-if="!state.useAgentJwt">
            <Input
              v-model="state.jwtIssuer"
              :label="t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_ISSUER.LABEL')"
              :placeholder="
                t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_ISSUER.PLACEHOLDER')
              "
            />

            <Input
              v-model="state.jwtAudience"
              :label="t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_AUDIENCE.LABEL')"
              :placeholder="
                t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_AUDIENCE.PLACEHOLDER')
              "
            />

            <Input
              v-model="state.jwtSecret"
              type="password"
              :label="t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_SECRET.LABEL')"
              :placeholder="
                t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_SECRET.PLACEHOLDER')
              "
              :message="formErrors.jwtSecret"
              :message-type="formErrors.jwtSecret ? 'error' : 'info'"
              @blur="v$.jwtSecret?.$touch"
            />

            <Input
              v-model="state.jwtTtl"
              :label="t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_TTL.LABEL')"
              :placeholder="
                t('INBOX_MGMT.ADD.VOICE.CUSTOM.JWT_TTL.PLACEHOLDER')
              "
            />
          </template>
        </template>
      </template>

      <div>
        <NextButton
          :is-loading="uiFlags.isCreating"
          :disabled="isSubmitDisabled"
          :label="t('INBOX_MGMT.ADD.VOICE.SUBMIT_BUTTON')"
          type="submit"
        />
      </div>
    </form>
  </div>
</template>
