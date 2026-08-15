import { createApp } from 'vue';
import 'dashboard/assets/scss/app.scss';
import './native.scss';
import { refreshActiveInstallation } from './platform/installationService';
import {
  restoreSession,
  syncShareContext,
} from './platform/authenticationService';
import { configureNativeEnvironment } from './platform/nativeEnvironmentService';
import { startNativeSystemBarSync } from './platform/nativeSystemBarService';

startNativeSystemBarSync();

const mountNativeShell = async () => {
  const { default: NativeApp } = await import('./NativeApp.vue');
  createApp(NativeApp).mount('#app');
};

const start = async () => {
  let installation;
  try {
    installation = await refreshActiveInstallation();
  } catch {
    await mountNativeShell();
    return;
  }

  if (!installation) {
    await mountNativeShell();
    return;
  }

  const session = await restoreSession(installation);
  if (!session) {
    await mountNativeShell();
    return;
  }

  await syncShareContext({ installation, user: session.user });
  configureNativeEnvironment({ installation, session });
  const { mountDashboard } = await import('../entrypoints/dashboard');
  await mountDashboard();
};

start();
