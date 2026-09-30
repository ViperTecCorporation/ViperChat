// Preserve the router's requested URL. Never force an update/reload here.
export const mountWebApp = async (app, router) => {
  try {
    window.viperBoot?.stage('session');
    await router.isReady();
    window.viperBoot?.stage('opening');
    app.mount('#app');
    // Allow the mounted screen to paint before removing the initial overlay.
    window.requestAnimationFrame(() => window.viperBoot?.finish());
  } catch (error) {
    window.viperBoot?.fail();
    throw error;
  }
};

export const onDocumentReady = callback => {
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', callback, { once: true });
  } else {
    callback();
  }
};
