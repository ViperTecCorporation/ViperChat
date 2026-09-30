/* Standalone: must execute before the dashboard modules and without Vite. */
(() => {
  const root = document.getElementById('dashboard-boot');
  if (!root) return;
  const status = document.getElementById('dashboard-boot-status');
  const notice = document.getElementById('dashboard-boot-notice');
  const retry = document.getElementById('dashboard-boot-retry');
  let finished = false;
  const showNotice = key => {
    if (finished) return;
    notice.textContent = root.dataset[key];
    notice.hidden = false;
    retry.hidden = false;
  };
  // A timeout is not a percentage or a failure: initialization may still finish.
  const timer = window.setTimeout(() => showNotice('slow'), 45000);
  const onAssetError = event => {
    if (
      event.target?.tagName === 'SCRIPT' ||
      event.target?.tagName === 'LINK'
    ) {
      showNotice('failed');
    }
  };
  const onModuleError = () => showNotice('failed');
  window.addEventListener('error', onAssetError, true);
  window.addEventListener('vite:preloadError', onModuleError);
  retry.addEventListener('click', () => window.location.reload());
  window.viperBoot = {
    stage(key) {
      if (!finished && root.dataset[key])
        status.textContent = root.dataset[key];
    },
    fail: onModuleError,
    finish() {
      if (finished) return;
      finished = true;
      window.clearTimeout(timer);
      window.removeEventListener('error', onAssetError, true);
      window.removeEventListener('vite:preloadError', onModuleError);
      root.remove();
      delete window.viperBoot;
    },
  };
})();
