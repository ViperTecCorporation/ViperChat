import { App } from '@capacitor/app';
import { Capacitor, registerPlugin } from '@capacitor/core';
import { readonly, ref } from 'vue';

const NativeShare = registerPlugin('NativeShare');
const pendingShare = ref(null);
let appStateListener;

const importFile = async sharedFile => {
  const response = await fetch(Capacitor.convertFileSrc(sharedFile.uri));
  if (!response.ok) throw new Error(`Falha ao ler ${sharedFile.name}.`);
  const blob = await response.blob();
  return new File([blob], sharedFile.name, {
    type: sharedFile.type || blob.type || 'application/octet-stream',
  });
};

export const refreshPendingShare = async () => {
  if (!Capacitor.isNativePlatform()) return null;

  const payload = await NativeShare.getPendingShare();
  if (!payload.available) return pendingShare.value;

  const files = await Promise.all((payload.files || []).map(importFile));
  pendingShare.value = {
    subject: payload.subject || '',
    text: payload.text || '',
    files,
    cachePaths: (payload.files || []).map(file => file.path),
  };
  return pendingShare.value;
};

export const initializeNativeShare = async () => {
  if (!window.chatwootConfig?.isNativeApp) return;
  await refreshPendingShare();
  appStateListener ||= await App.addListener('appStateChange', state => {
    if (state.isActive) refreshPendingShare();
  });
};

export const consumePendingShare = async () => {
  const payload = pendingShare.value;
  if (!payload) return null;

  pendingShare.value = null;
  await NativeShare.clearFiles({ paths: payload.cachePaths });
  return payload;
};

export const dismissPendingShare = () => consumePendingShare();
export const usePendingNativeShare = () => readonly(pendingShare);
