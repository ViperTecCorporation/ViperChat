import { createApp, h, ref } from 'vue';
import NativeStartup from './components/NativeStartup.vue';
import 'dashboard/assets/scss/app.scss';
import './native.scss';
import {
  loadActiveInstallation,
  refreshActiveInstallation,
} from './platform/installationService';
import {
  loadSession,
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
    installation = await loadActiveInstallation();
  } catch {
    await mountNativeShell();
    return;
  }

  if (!installation) {
    await mountNativeShell();
    return;
  }

  const session = await loadSession(installation.installationId);
  if (
    !session?.headers ||
    !session.user?.id ||
    Number(session.headers.expiry) * 1000 <= Date.now()
  ) {
    await mountNativeShell();
    return;
  }

  await syncShareContext({ installation, user: session.user });
  configureNativeEnvironment({ installation, session });
  const { mountDashboard } = await import('../entrypoints/dashboard');
  await mountDashboard();
  refreshActiveInstallation().catch(() => {});
};

const failed = ref(false);
const startupRoot = document.createElement('div');
document.body.append(startupRoot);
const startupApp = createApp({
  render: () =>
    h(NativeStartup, {
      failed: failed.value,
      // Explicit user retry only; never reload automatically after a network error.
      onRetry: () => window.location.reload(),
    }),
});
startupApp.mount(startupRoot);
start()
  .then(() => {
    startupApp.unmount();
    startupRoot.remove();
  })
  .catch(() => {
    failed.value = true;
  });
