import { createApp } from 'vue';
import 'dashboard/assets/scss/app.scss';
import { loadActiveInstallation } from './platform/installationService';
import { validateSession } from './platform/authenticationService';
import { configureNativeEnvironment } from './platform/nativeEnvironmentService';

const mountNativeShell = async () => {
  const { default: NativeApp } = await import('./NativeApp.vue');
  createApp(NativeApp).mount('#app');
};

const start = async () => {
  const installation = await loadActiveInstallation();
  if (!installation) {
    await mountNativeShell();
    return;
  }

  try {
    const session = await validateSession(installation);
    if (!session) {
      await mountNativeShell();
      return;
    }

    configureNativeEnvironment({ installation, session });
    const { mountDashboard } = await import('../entrypoints/dashboard');
    mountDashboard();
  } catch {
    await mountNativeShell();
  }
};

start();
