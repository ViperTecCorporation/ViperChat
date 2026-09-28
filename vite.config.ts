import { defineConfig } from 'vite';
import ruby from 'vite-plugin-ruby';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from './vite.shared';
import yaml from '@rollup/plugin-yaml';

let translationReloadTimer: ReturnType<typeof setTimeout> | undefined;

export default defineConfig({
  plugins: [
    ruby(),
    vue(vueOptions),
    yaml(),
    {
      name: 'local-development-translations',
      apply: 'serve',
      handleHotUpdate({ file, server }) {
        if (
          process.env.VIPER_DEV_PROXY === 'true' &&
          (translationReloadTimer ||
            file.replaceAll('\\', '/').includes('/dashboard/i18n/'))
        ) {
          // A sync can update many files. Restart once after the batch, outside
          // the HMR callback, so ongoing updates do not reference disposed state.
          clearTimeout(translationReloadTimer);
          translationReloadTimer = setTimeout(() => {
            translationReloadTimer = undefined;
            server.restart(true).catch(error => server.config.logger.error(String(error)));
          }, 2000);
          return [];
        }
      },
    },
  ],
  optimizeDeps:
    process.env.VIPER_DEV_PROXY === 'true'
      ? { include: ['dashboard/i18n', 'mediabunny'] }
      : undefined,
  server: {
    host: '0.0.0.0',
    port: 3036,
    strictPort: true,
    // Use the browser's URL/port behind the local gateway (HTTP or HTTPS).
    hmr: process.env.VIPER_DEV_PROXY === 'true' ? { clientPort: 0 } : undefined,
    allowedHosts: true,
    watch: {
      usePolling: process.env.VIPER_DEV_NATIVE_WATCH !== 'true',
      interval: 2500,
      awaitWriteFinish: {
        stabilityThreshold: 1000,
        pollInterval: 250,
      },
      ignored: [
        '**/.git/**',
        '**/node_modules/**',
        '**/.pnpm-store/**',
        '**/log/**',
        '**/tmp/**',
        '**/storage/**',
        '**/coverage/**',
        '**/public/packs/**',
        '**/spec/**',
        '**/specs/**',
        '**/vendor/**',
      ],
    },
  },
  css: {
    preprocessorOptions: {
      scss: {
        api: 'modern-compiler',
        quietDeps: true,
        silenceDeprecations: ['legacy-js-api', 'import'],
        logger: {
          warn: () => {},
          debug: () => {},
        },
      },
    },
  },
  resolve: { alias: aliases },
});
