<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useFontSize } from 'dashboard/composables/useFontSize';
import { useBranding } from 'shared/composables/useBranding';
import { clearCookiesOnLogout } from 'dashboard/store/utils/api.js';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import { parseBoolean } from '@chatwoot/utils';
import UserProfilePicture from './UserProfilePicture.vue';
import UserBasicDetails from './UserBasicDetails.vue';
import MessageSignature from './MessageSignature.vue';
import FontSize from './FontSize.vue';
import UserLanguageSelect from './UserLanguageSelect.vue';
import ChangePassword from './ChangePassword.vue';
import NotificationPreferences from './NotificationPreferences.vue';
import AudioNotifications from './AudioNotifications.vue';
import SectionLayout from '../account/components/SectionLayout.vue';
import AccessToken from './AccessToken.vue';
import MfaSettingsCard from './MfaSettingsCard.vue';
import Policy from 'dashboard/components/policy.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
} from 'dashboard/constants/permissions.js';

export default {
  components: {
    MessageSignature,
    SectionLayout,
    FontSize,
    UserLanguageSelect,
    UserProfilePicture,
    Policy,
    UserBasicDetails,
    RadioCard,
    ChangePassword,
    NotificationPreferences,
    AudioNotifications,
    AccessToken,
    MfaSettingsCard,
  },
  setup() {
    const { isEditorHotKeyEnabled, updateUISettings } = useUISettings();
    const { currentFontSize, updateFontSize } = useFontSize();
    const { replaceInstallationName } = useBranding();

    return {
      currentFontSize,
      updateFontSize,
      isEditorHotKeyEnabled,
      updateUISettings,
      replaceInstallationName,
    };
  },
  data() {
    return {
      avatarFile: '',
      avatarUrl: '',
      name: '',
      displayName: '',
      email: '',
      messageSignature: '',
      webrtcJwt: '',
      webrtcUsername: '',
      webrtcPassword: '',
      hotKeys: [
        {
          key: 'enter',
          title: this.$t(
            'PROFILE_SETTINGS.FORM.SEND_MESSAGE.CARD.ENTER_KEY.HEADING'
          ),
          description: this.$t(
            'PROFILE_SETTINGS.FORM.SEND_MESSAGE.CARD.ENTER_KEY.CONTENT'
          ),
          lightImage: '/assets/images/dashboard/profile/hot-key-enter.svg',
          darkImage: '/assets/images/dashboard/profile/hot-key-enter-dark.svg',
        },
        {
          key: 'cmd_enter',
          title: this.$t(
            'PROFILE_SETTINGS.FORM.SEND_MESSAGE.CARD.CMD_ENTER_KEY.HEADING'
          ),
          description: this.$t(
            'PROFILE_SETTINGS.FORM.SEND_MESSAGE.CARD.CMD_ENTER_KEY.CONTENT'
          ),
          lightImage: '/assets/images/dashboard/profile/hot-key-ctrl-enter.svg',
          darkImage:
            '/assets/images/dashboard/profile/hot-key-ctrl-enter-dark.svg',
        },
      ],
      notificationPermissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
      audioNotificationPermissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
    };
  },
  computed: {
    ...mapGetters({
      currentUser: 'getCurrentUser',
      currentUserId: 'getCurrentUserID',
      globalConfig: 'globalConfig/get',
    }),
    isMfaEnabled() {
      return parseBoolean(window.chatwootConfig?.isMfaEnabled);
    },
  },
  mounted() {
    if (this.currentUserId) {
      this.initializeUser();
    }
  },
  methods: {
    initializeUser() {
      this.name = this.currentUser.name;
      this.email = this.currentUser.email;
      this.avatarUrl = this.currentUser.avatar_url;
      this.displayName = this.currentUser.display_name;
      this.messageSignature = this.currentUser.message_signature;
      this.webrtcJwt = this.currentUser.custom_attributes?.webrtc_jwt || '';
      this.webrtcUsername =
        this.currentUser.custom_attributes?.webrtc_username || '';
      this.webrtcPassword = '';
    },
    async dispatchUpdate(payload, successMessage, errorMessage) {
      let alertMessage = '';
      try {
        // eslint-disable-next-line no-console
        console.log('[Profile] dispatchUpdate', {
          hasAvatar: !!payload.avatar,
          hasCustomAttributes: !!payload.custom_attributes,
        });
        await this.$store.dispatch('updateProfile', payload);
        alertMessage = successMessage;

        return true; // return the value so that the status can be known
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error('[Profile] dispatchUpdate error', { error });
        alertMessage = parseAPIErrorResponse(error) || errorMessage;

        return false; // return the value so that the status can be known
      } finally {
        useAlert(alertMessage);
      }
    },
    async updateProfile(userAttributes) {
      const { name, email, displayName, customAttributes } = userAttributes;
      const hasEmailChanged = this.currentUser.email !== email;
      this.name = name || this.name;
      this.email = email || this.email;
      this.displayName = displayName || this.displayName;
      this.webrtcJwt = customAttributes?.webrtc_jwt ?? this.webrtcJwt;
      this.webrtcUsername =
        customAttributes?.webrtc_username ?? this.webrtcUsername;
      if (customAttributes?.webrtc_password) {
        this.webrtcPassword = '';
      }

      // eslint-disable-next-line no-console
      console.log('[Profile] updateProfile', {
        hasEmailChanged,
        hasWebrtcJwt: !!customAttributes?.webrtc_jwt,
        hasWebrtcUsername: !!customAttributes?.webrtc_username,
        hasWebrtcPassword: !!customAttributes?.webrtc_password,
      });
      const updatePayload = {
        name: this.name,
        email: this.email,
        displayName: this.displayName,
        avatar: this.avatarFile,
        custom_attributes: customAttributes,
      };

      const success = await this.dispatchUpdate(
        updatePayload,
        hasEmailChanged
          ? this.$t('PROFILE_SETTINGS.AFTER_EMAIL_CHANGED')
          : this.$t('PROFILE_SETTINGS.UPDATE_SUCCESS'),
        this.$t('RESET_PASSWORD.API.ERROR_MESSAGE')
      );

      if (hasEmailChanged && success) clearCookiesOnLogout();
    },
    async updateSignature(signature) {
      const payload = { message_signature: signature };
      let successMessage = this.$t(
        'PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.API_SUCCESS'
      );
      let errorMessage = this.$t(
        'PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.API_ERROR'
      );

      await this.dispatchUpdate(payload, successMessage, errorMessage);
    },
    updateProfilePicture({ file, url }) {
      this.avatarFile = file;
      this.avatarUrl = url;
    },
    async deleteProfilePicture() {
      try {
        await this.$store.dispatch('deleteAvatar');
        this.avatarUrl = '';
        this.avatarFile = '';
        useAlert(this.$t('PROFILE_SETTINGS.AVATAR_DELETE_SUCCESS'));
      } catch (error) {
        useAlert(this.$t('PROFILE_SETTINGS.AVATAR_DELETE_FAILED'));
      }
    },
    toggleHotKey(key) {
      this.hotKeys = this.hotKeys.map(hotKey =>
        hotKey.key === key ? { ...hotKey, active: !hotKey.active } : hotKey
      );
      this.updateUISettings({ editor_message_key: key });
      useAlert(this.$t('PROFILE_SETTINGS.FORM.SEND_MESSAGE.UPDATE_SUCCESS'));
    },
    async onCopyToken(value) {
      await copyTextToClipboard(value);
      useAlert(this.$t('COMPONENTS.CODE.COPY_SUCCESSFUL'));
    },
    async resetAccessToken() {
      const success = await this.$store.dispatch('resetAccessToken');
      if (success) {
        useAlert(this.$t('PROFILE_SETTINGS.FORM.ACCESS_TOKEN.RESET_SUCCESS'));
      } else {
        useAlert(this.$t('PROFILE_SETTINGS.FORM.ACCESS_TOKEN.RESET_ERROR'));
      }
    },
  },
};
</script>

<template>
  <div class="grid py-16 px-5 font-inter mx-auto gap-16 sm:max-w-screen-md">
    <div class="flex flex-col gap-6">
      <h2 class="text-2xl font-medium text-n-slate-12">
        {{ $t('PROFILE_SETTINGS.TITLE') }}
      </h2>
      <UserProfilePicture
        :src="avatarUrl"
        :name="name"
        @change="updateProfilePicture"
        @delete="deleteProfilePicture"
      />
      <UserBasicDetails
        :name="name"
        :display-name="displayName"
        :email="email"
        :email-enabled="!globalConfig.disableUserProfileUpdate"
        :webrtc-jwt="webrtcJwt"
        :webrtc-username="webrtcUsername"
        :webrtc-password="webrtcPassword"
        @update-user="updateProfile"
      />
    </div>
    <SectionLayout
      :title="$t('PROFILE_SETTINGS.FORM.INTERFACE_SECTION.TITLE')"
      :description="
        replaceInstallationName(
          $t('PROFILE_SETTINGS.FORM.INTERFACE_SECTION.NOTE')
        )
      "
    >
      <div class="flex flex-col gap-6 items-start">
        <FontSize
          :value="currentFontSize"
          :label="$t('PROFILE_SETTINGS.FORM.INTERFACE_SECTION.FONT_SIZE.TITLE')"
          :description="
            $t('PROFILE_SETTINGS.FORM.INTERFACE_SECTION.FONT_SIZE.NOTE')
          "
          @change="updateFontSize"
        />
        <UserLanguageSelect
          :label="$t('PROFILE_SETTINGS.FORM.INTERFACE_SECTION.LANGUAGE.TITLE')"
          :description="
            $t('PROFILE_SETTINGS.FORM.INTERFACE_SECTION.LANGUAGE.NOTE')
          "
        />
      </div>
    </SectionLayout>
    <SectionLayout
      with-border
      :title="$t('PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.TITLE')"
      :description="$t('PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.NOTE')"
    >
      <MessageSignature
        :message-signature="messageSignature"
        @update-signature="updateSignature"
      />
    </SectionLayout>
    <SectionLayout
      with-border
      :title="$t('PROFILE_SETTINGS.FORM.SEND_MESSAGE.TITLE')"
      :description="$t('PROFILE_SETTINGS.FORM.SEND_MESSAGE.NOTE')"
    >
      <div
        class="flex flex-col justify-between w-full gap-5 sm:gap-4 sm:flex-row"
      >
        <RadioCard
          v-for="hotKey in hotKeys"
          :id="hotKey.key"
          :key="hotKey.key"
          :label="hotKey.title"
          :description="hotKey.description"
          :is-active="isEditorHotKeyEnabled(hotKey.key)"
          class="sm:flex-1"
          @select="toggleHotKey"
        >
          <img
            :src="hotKey.lightImage"
            :alt="`Light themed image for ${hotKey.title}`"
            class="block object-cover w-full dark:hidden"
          />
          <img
            :src="hotKey.darkImage"
            :alt="`Dark themed image for ${hotKey.title}`"
            class="hidden object-cover w-full dark:block"
          />
        </RadioCard>
      </div>
    </SectionLayout>
    <SectionLayout
      v-if="!globalConfig.disableUserProfileUpdate"
      with-border
      :title="$t('PROFILE_SETTINGS.FORM.PASSWORD_SECTION.TITLE')"
      description=""
    >
      <ChangePassword />
    </SectionLayout>
    <SectionLayout
      v-if="isMfaEnabled"
      with-border
      :title="$t('PROFILE_SETTINGS.FORM.SECURITY_SECTION.TITLE')"
      :description="$t('PROFILE_SETTINGS.FORM.SECURITY_SECTION.NOTE')"
    >
      <MfaSettingsCard />
    </SectionLayout>
    <Policy :permissions="audioNotificationPermissions">
      <SectionLayout
        with-border
        :title="$t('PROFILE_SETTINGS.FORM.AUDIO_NOTIFICATIONS_SECTION.TITLE')"
        :description="
          $t('PROFILE_SETTINGS.FORM.AUDIO_NOTIFICATIONS_SECTION.NOTE')
        "
      >
        <AudioNotifications />
      </SectionLayout>
    </Policy>
    <Policy :permissions="notificationPermissions">
      <SectionLayout
        with-border
        :title="$t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.TITLE')"
        description=""
      >
        <NotificationPreferences />
      </SectionLayout>
    </Policy>
    <SectionLayout
      with-border
      :title="$t('PROFILE_SETTINGS.FORM.ACCESS_TOKEN.TITLE')"
      :description="
        replaceInstallationName($t('PROFILE_SETTINGS.FORM.ACCESS_TOKEN.NOTE'))
      "
    >
      <AccessToken
        :value="currentUser.access_token"
        @on-copy="onCopyToken"
        @on-reset="resetAccessToken"
      />
    </SectionLayout>
  </div>
</template>
