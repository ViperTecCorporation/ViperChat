import { defineConfig } from 'vite';
import ruby from 'vite-plugin-ruby';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from './vite.shared';
import yaml from '@rollup/plugin-yaml';

export default defineConfig({
  plugins: [ruby(), vue(vueOptions), yaml()],
  server: {
    host: '0.0.0.0',
    port: 3036,
    strictPort: true,
    allowedHosts: true,
    watch: {
      usePolling: true,
      interval: 2500,
      awaitWriteFinish: {
        stabilityThreshold: 1000,
        pollInterval: 250,
      },
      ignored: [
        '**/.git/**',
        '**/node_modules/**',
        '**/log/**',
        '**/tmp/**',
        '**/storage/**',
        '**/coverage/**',
        '**/public/packs/**',
        '**/spec/**',
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
