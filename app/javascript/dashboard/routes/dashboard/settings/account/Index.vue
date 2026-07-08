<script>
import { computed } from 'vue';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useConfig } from 'dashboard/composables/useConfig';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from '../../../../featureFlags';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import NextInput from 'next/input/Input.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Switch from 'next/switch/Switch.vue';
import ColorPicker from 'dashboard/components-next/colorpicker/ColorPicker.vue';
import AccountId from './components/AccountId.vue';
import BuildInfo from './components/BuildInfo.vue';
import AccountDelete from './components/AccountDelete.vue';
import AudioTranscription from './components/AudioTranscription.vue';
import DeletedMessageContent from './components/DeletedMessageContent.vue';
import SectionLayout from './components/SectionLayout.vue';

export default {
  components: {
    BaseSettingsHeader,
    NextButton,
    AccountId,
    BuildInfo,
    AccountDelete,
    AudioTranscription,
    DeletedMessageContent,
    SectionLayout,
    // eslint-disable-next-line vue/no-reserved-component-names
    Switch,
    WithLabel,
    NextInput,
    ColorPicker,
  },
  setup() {
    const { updateUISettings, uiSettings } = useUISettings();
    const { enabledLanguages } = useConfig();
    const { accountId } = useAccount();
    const v$ = useVuelidate();
    const openWaitingConversationsByDefault = computed({
      get: () =>
        uiSettings.value.open_waiting_conversations_by_default ?? false,
      set: value =>
        updateUISettings({
          open_waiting_conversations_by_default: value,
        }),
    });
    const activeTheme = computed({
      get: () => uiSettings.value.active_theme || 'default',
      set: value => {
        updateUISettings({ active_theme: value });
        if (value !== 'custom') {
          updateUISettings({ custom_brand_color: null });
        }
      },
    });
    const customBrandColor = computed({
      get: () => uiSettings.value.custom_brand_color || '#2781f6',
      set: value => {
        updateUISettings({ custom_brand_color: value, active_theme: 'custom' });
      },
    });

    return {
      updateUISettings,
      uiSettings,
      v$,
      enabledLanguages,
      accountId,
      openWaitingConversationsByDefault,
      activeTheme,
      customBrandColor,
    };
  },
  data() {
    return {
      id: '',
      name: '',
      locale: 'en',
      domain: '',
      supportEmail: '',
      features: {},
    };
  },
  validations: {
    name: {
      required,
    },
    locale: {
      required,
    },
  },
  computed: {
    ...mapGetters({
      getAccount: 'accounts/getAccount',
      uiFlags: 'accounts/getUIFlags',
      isFeatureEnabledonAccount: 'accounts/isFeatureEnabledonAccount',
      isOnChatwootCloud: 'globalConfig/isOnChatwootCloud',
    }),
    showAudioTranscriptionConfig() {
      return this.isFeatureEnabledonAccount(
        this.accountId,
        FEATURE_FLAGS.CAPTAIN
      );
    },
    languagesSortedByCode() {
      const enabledLanguages = [...this.enabledLanguages];
      return enabledLanguages.sort((l1, l2) =>
        l1.iso_639_1_code.localeCompare(l2.iso_639_1_code)
      );
    },
    isUpdating() {
      return this.uiFlags.isUpdating;
    },
    featureInboundEmailEnabled() {
      return !!this.features?.inbound_emails;
    },
    featureCustomReplyDomainEnabled() {
      return (
        this.featureInboundEmailEnabled && !!this.features.custom_reply_domain
      );
    },
    featureCustomReplyEmailEnabled() {
      return (
        this.featureInboundEmailEnabled && !!this.features.custom_reply_email
      );
    },
    currentAccount() {
      return this.getAccount(this.accountId) || {};
    },
  },
  mounted() {
    this.initializeAccount();
  },
  methods: {
    async initializeAccount() {
      try {
        const { name, locale, id, domain, support_email, features } =
          this.getAccount(this.accountId);

        const effectiveLocale = this.uiSettings?.locale || locale;
        if (effectiveLocale) {
          this.$root.$i18n.locale = effectiveLocale;
        }
        this.name = name;
        this.locale = locale;
        this.id = id;
        this.domain = domain;
        this.supportEmail = support_email;
        this.features = features;
      } catch (error) {
        // Ignore error
      }
    },

    async updateAccount() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        useAlert(this.$t('GENERAL_SETTINGS.FORM.ERROR'));
        return;
      }
      try {
        await this.$store.dispatch('accounts/update', {
          locale: this.locale,
          name: this.name,
          domain: this.domain,
          support_email: this.supportEmail,
        });
        // If user locale is set, update the locale with user locale
        const updatedLocale = this.uiSettings?.locale || this.locale;
        if (updatedLocale) {
          this.$root.$i18n.locale = updatedLocale;
        }
        this.getAccount(this.id).locale = this.locale;
        useAlert(this.$t('GENERAL_SETTINGS.UPDATE.SUCCESS'));
      } catch (error) {
        useAlert(this.$t('GENERAL_SETTINGS.UPDATE.ERROR'));
      }
    },
  },
};
</script>

<template>
  <div class="flex flex-col max-w-2xl mx-auto w-full">
    <BaseSettingsHeader
      :title="$t('GENERAL_SETTINGS.TITLE')"
      :description="$t('GENERAL_SETTINGS.FORM.GENERAL_SECTION.NOTE')"
    />
    <div class="flex-grow flex-shrink min-w-0 mt-3">
      <SectionLayout
        :title="$t('GENERAL_SETTINGS.FORM.GENERAL_SECTION.TITLE')"
        :description="$t('GENERAL_SETTINGS.FORM.GENERAL_SECTION.NOTE')"
        class="!pt-0"
      >
        <form
          v-if="!uiFlags.isFetchingItem"
          class="grid gap-4"
          @submit.prevent="updateAccount"
        >
          <WithLabel
            name="account-name"
            :has-error="v$.name.$error"
            :label="$t('GENERAL_SETTINGS.FORM.NAME.LABEL')"
            :error-message="$t('GENERAL_SETTINGS.FORM.NAME.ERROR')"
          >
            <NextInput
              v-model="name"
              type="text"
              class="w-full"
              :placeholder="$t('GENERAL_SETTINGS.FORM.NAME.PLACEHOLDER')"
              @blur="v$.name.$touch"
            />
          </WithLabel>
          <WithLabel
            name="account-language"
            :has-error="v$.locale.$error"
            :label="$t('GENERAL_SETTINGS.FORM.LANGUAGE.LABEL')"
            :error-message="$t('GENERAL_SETTINGS.FORM.LANGUAGE.ERROR')"
          >
            <select v-model="locale" class="!mb-0 text-sm">
              <option
                v-for="lang in languagesSortedByCode"
                :key="lang.iso_639_1_code"
                :value="lang.iso_639_1_code"
              >
                {{ lang.name }}
              </option>
            </select>
          </WithLabel>
          <WithLabel
            v-if="featureCustomReplyDomainEnabled"
            name="account-domain"
            :label="$t('GENERAL_SETTINGS.FORM.DOMAIN.LABEL')"
          >
            <NextInput
              v-model="domain"
              type="text"
              class="w-full"
              :placeholder="$t('GENERAL_SETTINGS.FORM.DOMAIN.PLACEHOLDER')"
            />
            <template #help>
              {{
                featureInboundEmailEnabled &&
                $t('GENERAL_SETTINGS.FORM.FEATURES.INBOUND_EMAIL_ENABLED')
              }}

              {{
                featureCustomReplyDomainEnabled &&
                $t('GENERAL_SETTINGS.FORM.FEATURES.CUSTOM_EMAIL_DOMAIN_ENABLED')
              }}
            </template>
          </WithLabel>
          <WithLabel
            v-if="featureCustomReplyEmailEnabled"
            name="account-support-email"
            :label="$t('GENERAL_SETTINGS.FORM.SUPPORT_EMAIL.LABEL')"
          >
            <NextInput
              v-model="supportEmail"
              type="text"
              class="w-full"
              :placeholder="
                $t('GENERAL_SETTINGS.FORM.SUPPORT_EMAIL.PLACEHOLDER')
              "
            />
          </WithLabel>
          <div>
            <NextButton blue :is-loading="isUpdating" type="submit">
              {{ $t('GENERAL_SETTINGS.SUBMIT') }}
            </NextButton>
          </div>
        </form>
      </SectionLayout>

      <woot-loading-state v-if="uiFlags.isFetchingItem" />
    </div>
    <AudioTranscription v-if="showAudioTranscriptionConfig" />
    <DeletedMessageContent />
    <SectionLayout
      with-border
      :title="$t('GENERAL_SETTINGS.FORM.BRAND_COLOR_SECTION.TITLE')"
      :description="$t('GENERAL_SETTINGS.FORM.BRAND_COLOR_SECTION.NOTE')"
    >
      <div class="flex flex-col gap-4">
        <div class="flex gap-4">
          <button
            class="flex items-center gap-2 px-4 py-3 border border-solid rounded-lg text-sm font-medium transition-all cursor-pointer"
            :class="
              activeTheme === 'default'
                ? 'border-n-brand bg-n-brand/5 text-n-brand'
                : 'border-n-weak bg-n-surface-2 text-n-slate-12 hover:border-n-strong'
            "
            @click="activeTheme = 'default'"
          >
            <span class="w-4 h-4 rounded-sm bg-[#2781f6] inline-block" />
            {{ $t('GENERAL_SETTINGS.FORM.BRAND_COLOR_SECTION.THEME_ORIGINAL') }}
          </button>
          <button
            class="flex items-center gap-2 px-4 py-3 border border-solid rounded-lg text-sm font-medium transition-all cursor-pointer"
            :class="
              activeTheme === 'viper'
                ? 'border-n-brand bg-n-brand/5 text-n-brand'
                : 'border-n-weak bg-n-surface-2 text-n-slate-12 hover:border-n-strong'
            "
            @click="activeTheme = 'viper'"
          >
            <span class="w-4 h-4 rounded-sm bg-[#6f3935] inline-block" />
            {{ $t('GENERAL_SETTINGS.FORM.BRAND_COLOR_SECTION.THEME_VIPER') }}
          </button>
          <button
            class="flex items-center gap-2 px-4 py-3 border border-solid rounded-lg text-sm font-medium transition-all cursor-pointer"
            :class="
              activeTheme === 'glow'
                ? 'border-n-brand bg-n-brand/5 text-n-brand'
                : 'border-n-weak bg-n-surface-2 text-n-slate-12 hover:border-n-strong'
            "
            @click="activeTheme = 'glow'"
          >
            <span class="w-4 h-4 rounded-sm bg-[#7c3aed] inline-block" />
            {{ $t('GENERAL_SETTINGS.FORM.BRAND_COLOR_SECTION.THEME_GLOW') }}
          </button>
        </div>
        <div class="flex items-center gap-4 mt-2">
          <ColorPicker v-model="customBrandColor" />
          <div class="w-40">
            <NextInput
              v-model="customBrandColor"
              type="text"
              placeholder="#2781f6"
              class="w-full"
            />
          </div>
          <span class="text-sm text-n-slate-11">
            {{ $t('GENERAL_SETTINGS.FORM.BRAND_COLOR_SECTION.CUSTOM') }}
          </span>
        </div>
      </div>
    </SectionLayout>
    <SectionLayout
      with-border
      :title="$t('GENERAL_SETTINGS.FORM.WAITING_CONVERSATIONS_SECTION.TITLE')"
      :description="
        $t('GENERAL_SETTINGS.FORM.WAITING_CONVERSATIONS_SECTION.NOTE')
      "
    >
      <template #headerActions>
        <div class="flex justify-end">
          <Switch v-model="openWaitingConversationsByDefault" />
        </div>
      </template>
    </SectionLayout>
    <AccountId />
    <div v-if="!uiFlags.isFetchingItem && isOnChatwootCloud">
      <AccountDelete />
    </div>
    <BuildInfo />
  </div>
</template>
