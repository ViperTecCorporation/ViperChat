import path from 'path';
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import yaml from '@rollup/plugin-yaml';
import { aliases, vueOptions } from './vite.shared';

export default defineConfig({
  root: path.resolve('./app/javascript/native'),
  plugins: [vue(vueOptions), yaml()],
  resolve: { alias: aliases },
  build: {
    outDir: path.resolve('./dist-mobile'),
    emptyOutDir: true,
  },
});
