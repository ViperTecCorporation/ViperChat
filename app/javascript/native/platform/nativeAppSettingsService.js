import { registerPlugin } from '@capacitor/core';

const NativeAppSettings = registerPlugin('NativeAppSettings');

export const openNativeNotificationSettings = ({ channelId } = {}) =>
  NativeAppSettings.openNotificationSettings({
    ...(channelId && { channelId }),
  });
