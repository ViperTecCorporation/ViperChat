<script setup>
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n, I18nT } from 'vue-i18n';
import Twilio from './Twilio.vue';
import Unoapi from './Unoapi.vue';
import ThreeSixtyDialogWhatsapp from './360DialogWhatsapp.vue';
import CloudWhatsapp from './CloudWhatsapp.vue';
import WhatsappEmbeddedSignup from './WhatsappEmbeddedSignup.vue';
import ChannelSelector from 'dashboard/components/ChannelSelector.vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const { currentAccount } = useAccount();
const providerAllowed = provider => {
  const features = currentAccount.value?.features;
  if (!features) return false;
  return provider === 'unoapi'
    ? !features.disable_channel_unoapi
    : Boolean(features.channel_whatsapp);
};

const PROVIDER_TYPES = {
  WHATSAPP: 'whatsapp',
  TWILIO: 'twilio',
  WHATSAPP_CLOUD: 'whatsapp_cloud',
  WHATSAPP_EMBEDDED: 'whatsapp_embedded',
  WHATSAPP_MANUAL: 'whatsapp_manual',
  THREE_SIXTY_DIALOG: '360dialog',
  UNOAPI: 'unoapi',
};

const hasWhatsappAppId = computed(() => {
  return (
    window.chatwootConfig?.whatsappAppId &&
    window.chatwootConfig.whatsappAppId !== 'none'
  );
});

const selectedProvider = computed(() => route.query.provider);

const showProviderSelection = computed(() => !selectedProvider.value);

const showConfiguration = computed(
  () =>
    Boolean(selectedProvider.value) && providerAllowed(selectedProvider.value)
);

const shouldShowWhatsappEmbeddedSignup = computed(() => {
  return (
    selectedProvider.value === PROVIDER_TYPES.WHATSAPP &&
    hasWhatsappAppId.value &&
    currentAccount.value?.features?.[
      FEATURE_FLAGS.WHATSAPP_EMBEDDED_SIGNUP_INBOX_CREATION
    ]
  );
});

const availableProviders = computed(() =>
  [
    {
      key: PROVIDER_TYPES.WHATSAPP,
      title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSAPP_CLOUD'),
      description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSAPP_CLOUD_DESC'),
      icon: 'i-woot-whatsapp',
    },
    {
      key: PROVIDER_TYPES.TWILIO,
      title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.TWILIO'),
      description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.TWILIO_DESC'),
      icon: 'i-woot-twilio',
    },
    {
      key: PROVIDER_TYPES.UNOAPI,
      title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.UNOAPI'),
      description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.UNOAPI'),
      icon: 'i-woot-whatsapp',
    },
  ].filter(provider => providerAllowed(provider.key))
);

const selectProvider = providerValue => {
  if (!providerAllowed(providerValue)) return;
  router.push({
    name: route.name,
    params: route.params,
    query: { provider: providerValue },
  });
};

const shouldShowCloudWhatsapp = provider => {
  return (
    provider === PROVIDER_TYPES.WHATSAPP_MANUAL ||
    (provider === PROVIDER_TYPES.WHATSAPP &&
      !shouldShowWhatsappEmbeddedSignup.value)
  );
};

const handleManualLinkClick = () => {
  selectProvider(PROVIDER_TYPES.WHATSAPP_MANUAL);
};
</script>

<template>
  <div class="overflow-auto col-span-6 p-6 w-full h-full">
    <div v-if="showProviderSelection && availableProviders.length">
      <div class="mb-10 text-left">
        <h1 class="mb-2 text-lg font-medium text-n-slate-12">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.SELECT_PROVIDER.TITLE') }}
        </h1>
        <p class="text-sm leading-relaxed text-n-slate-11">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.SELECT_PROVIDER.DESCRIPTION') }}
        </p>
      </div>

      <div class="flex flex-wrap gap-6 justify-start">
        <ChannelSelector
          v-for="provider in availableProviders"
          :key="provider.key"
          :title="provider.title"
          :description="provider.description"
          :icon="provider.icon"
          @click="selectProvider(provider.key)"
        />
      </div>
    </div>

    <p
      v-else-if="!showConfiguration"
      role="alert"
      class="text-sm text-n-slate-11"
    >
      {{ $t('INBOX_MGMT.ADD.WHATSAPP.CHANNEL_RESTRICTED') }}
    </p>
    <div v-else-if="showConfiguration">
      <div class="px-6 py-5 rounded-2xl border border-n-weak">
        <div v-if="shouldShowWhatsappEmbeddedSignup">
          <WhatsappEmbeddedSignup />

          <!-- Manual setup fallback option -->
          <div class="pt-6 mt-6 border-t border-n-weak">
            <I18nT
              keypath="INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.MANUAL_FALLBACK"
              tag="p"
              class="text-sm text-n-slate-11"
            >
              <template #link>
                <a
                  href="#"
                  class="underline text-n-brand"
                  @click.prevent="handleManualLinkClick"
                >
                  {{
                    $t(
                      'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.MANUAL_LINK_TEXT'
                    )
                  }}
                </a>
              </template>
            </I18nT>
          </div>
        </div>

        <!-- Show manual setup -->
        <CloudWhatsapp v-else-if="shouldShowCloudWhatsapp(selectedProvider)" />

        <!-- Other providers -->
        <Twilio
          v-else-if="selectedProvider === PROVIDER_TYPES.TWILIO"
          type="whatsapp"
        />
        <ThreeSixtyDialogWhatsapp
          v-else-if="selectedProvider === PROVIDER_TYPES.THREE_SIXTY_DIALOG"
        />
        <Unoapi v-else-if="selectedProvider === PROVIDER_TYPES.UNOAPI" />
        <CloudWhatsapp v-else />
      </div>
    </div>
  </div>
</template>
