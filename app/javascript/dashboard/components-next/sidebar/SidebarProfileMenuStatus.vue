<script setup>
import { computed, h, onMounted, ref } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import wootConstants from 'dashboard/constants/globals';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { useImpersonation } from 'dashboard/composables/useImpersonation';
import {
  hasPushPermissions,
  requestPushPermissions,
  verifyServiceWorkerExistence,
} from 'dashboard/helper/pushHelper';

import {
  DropdownContainer,
  DropdownBody,
  DropdownSection,
  DropdownItem,
} from 'next/dropdown-menu/base';
import Icon from 'next/icon/Icon.vue';
import Button from 'next/button/Button.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';

const { t } = useI18n();
const store = useStore();
const currentUserAvailability = useMapGetter('getCurrentUserAvailability');
const currentAccountId = useMapGetter('getCurrentAccountId');
const currentUserAutoOffline = useMapGetter('getCurrentUserAutoOffline');
const browserPushEnabled = ref(false);

const { isImpersonating } = useImpersonation();

const { AVAILABILITY_STATUS_KEYS } = wootConstants;
const statusList = computed(() => {
  return [
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.ONLINE'),
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.BUSY'),
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.OFFLINE'),
  ];
});

const statusColors = ['bg-n-teal-9', 'bg-n-amber-9', 'bg-n-slate-9'];

const availabilityStatuses = computed(() => {
  return statusList.value.map((statusLabel, index) => ({
    label: statusLabel,
    value: AVAILABILITY_STATUS_KEYS[index],
    color: statusColors[index],
    icon: h('span', { class: [statusColors[index], 'size-[12px] rounded'] }),
    active: currentUserAvailability.value === AVAILABILITY_STATUS_KEYS[index],
  }));
});

const activeStatus = computed(() => {
  return availabilityStatuses.value.find(status => status.active);
});

const autoOfflineToggle = computed({
  get: () => currentUserAutoOffline.value,
  set: autoOffline => {
    store.dispatch('updateAutoOffline', {
      accountId: currentAccountId.value,
      autoOffline,
    });
  },
});

const hasPushAPISupport =
  'Notification' in window &&
  'serviceWorker' in navigator &&
  'PushManager' in window;

const refreshBrowserPushStatus = () => {
  if (!hasPushAPISupport || !hasPushPermissions()) {
    browserPushEnabled.value = false;
    return;
  }

  verifyServiceWorkerExistence(registration => {
    registration.pushManager
      .getSubscription()
      .then(subscription => {
        browserPushEnabled.value = Boolean(subscription);
      })
      .catch(() => {
        browserPushEnabled.value = false;
      });
  });
};

const disableBrowserPush = () => {
  browserPushEnabled.value = false;
  verifyServiceWorkerExistence(registration => {
    registration.pushManager
      .getSubscription()
      .then(subscription => subscription?.unsubscribe())
      .catch(() => {});
  });
};

const browserPushToggle = computed({
  get: () => browserPushEnabled.value,
  set: enabled => {
    if (!enabled) {
      disableBrowserPush();
      return;
    }

    requestPushPermissions({
      onSuccess: () => {
        browserPushEnabled.value = true;
      },
    });
  },
});

function changeAvailabilityStatus(availability) {
  if (isImpersonating.value) {
    useAlert(t('PROFILE_SETTINGS.FORM.AVAILABILITY.IMPERSONATING_ERROR'));
    return;
  }
  try {
    store.dispatch('updateAvailability', {
      availability,
      account_id: currentAccountId.value,
    });
  } catch (error) {
    useAlert(t('PROFILE_SETTINGS.FORM.AVAILABILITY.SET_AVAILABILITY_ERROR'));
  }
}

onMounted(refreshBrowserPushStatus);
</script>

<template>
  <DropdownSection class="[&>ul]:overflow-visible">
    <div class="grid gap-0">
      <DropdownItem preserve-open class="gap-1">
        <div class="flex-grow flex items-center gap-1 min-w-0">
          {{ $t('SIDEBAR.SET_YOUR_AVAILABILITY') }}
        </div>
        <DropdownContainer class="shrink-0">
          <template #trigger="{ toggle }">
            <Button
              size="sm"
              color="slate"
              variant="faded"
              icon="i-lucide-chevron-down"
              trailing-icon
              @click="toggle"
            >
              <div class="flex gap-1 items-center min-w-0 text-sm">
                <div class="p-1 flex-shrink-0">
                  <div class="size-2 rounded-sm" :class="activeStatus.color" />
                </div>
                <span class="truncate max-w-[7rem]">
                  {{ activeStatus.label }}
                </span>
              </div>
            </Button>
          </template>
          <DropdownBody class="min-w-32 z-20">
            <DropdownItem
              v-for="status in availabilityStatuses"
              :key="status.value"
              :label="status.label"
              :icon="status.icon"
              class="cursor-pointer"
              @click="changeAvailabilityStatus(status.value)"
            />
          </DropdownBody>
        </DropdownContainer>
      </DropdownItem>
      <DropdownItem v-if="hasPushAPISupport" preserve-open>
        <div class="flex flex-grow items-center min-w-0 gap-2">
          <Icon
            icon="i-lucide-bell"
            class="flex-shrink-0 size-4 text-n-slate-11"
          />
          {{ $t('SIDEBAR.PUSH_NOTIFICATIONS') }}
        </div>
        <ToggleSwitch v-model="browserPushToggle" />
      </DropdownItem>
      <DropdownItem>
        <div class="flex-grow min-w-0">
          {{ $t('SIDEBAR.SET_AUTO_OFFLINE.TEXT') }}
          <Icon
            v-tooltip.top="$t('SIDEBAR.SET_AUTO_OFFLINE.INFO_SHORT')"
            icon="i-lucide-info"
            class="inline-block align-middle ms-1 size-4 text-n-slate-10"
          />
        </div>
        <ToggleSwitch v-model="autoOfflineToggle" />
      </DropdownItem>
    </div>
  </DropdownSection>
</template>
