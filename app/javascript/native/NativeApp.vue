<script setup>
import { onMounted, ref } from 'vue';
import {
  configureInstallation,
  getDefaultServerUrl,
  loadActiveInstallation,
  removeInstallation,
} from './platform/installationService';
import { clearSession, login } from './platform/authenticationService';
import { getRuntimeInfo } from './platform/runtimeService';

const serverUrl = ref(getDefaultServerUrl());
const installation = ref(null);
const errorMessage = ref('');
const isConnecting = ref(false);
const isLoggingIn = ref(false);
const credentials = ref({ email: '', password: '' });
const runtime = getRuntimeInfo();
const copy = {
  mark: 'V',
  title: 'ViperChat',
  description: 'Conecte o aplicativo à instalação da sua empresa.',
  server: 'Servidor',
  connecting: 'Validando…',
  connect: 'Conectar',
  connected: 'Servidor validado',
  email: 'E-mail',
  password: 'Senha',
  login: 'Entrar',
  loggingIn: 'Entrando…',
  changeServer: 'Trocar servidor',
  runtime: 'Runtime:',
};

onMounted(async () => {
  installation.value = await loadActiveInstallation();
  if (installation.value) serverUrl.value = installation.value.baseUrl;
});

const connect = async () => {
  errorMessage.value = '';
  isConnecting.value = true;

  try {
    installation.value = await configureInstallation(serverUrl.value);
  } catch (error) {
    errorMessage.value = error.message;
  } finally {
    isConnecting.value = false;
  }
};

const signIn = async () => {
  errorMessage.value = '';
  isLoggingIn.value = true;

  try {
    await login({
      installation: installation.value,
      ...credentials.value,
    });
    window.location.reload();
  } catch (error) {
    errorMessage.value = error.message;
  } finally {
    isLoggingIn.value = false;
  }
};

const changeServer = async () => {
  if (!installation.value) return;

  await clearSession(installation.value.installationId);
  await removeInstallation(installation.value.installationId);
  installation.value = null;
  credentials.value = { email: '', password: '' };
  errorMessage.value = '';
  serverUrl.value = getDefaultServerUrl();
};
</script>

<template>
  <main
    class="flex min-h-screen items-center justify-center bg-n-background p-6"
  >
    <section
      class="w-full max-w-md rounded-2xl border border-n-weak bg-n-solid-2 p-6 shadow-lg"
    >
      <div class="mb-8 flex flex-col items-center text-center">
        <div
          class="mb-4 flex size-16 items-center justify-center rounded-2xl bg-n-brand text-2xl font-bold text-white"
        >
          {{ copy.mark }}
        </div>
        <h1 class="text-2xl font-semibold text-n-slate-12">
          {{ copy.title }}
        </h1>
        <p class="mt-2 text-sm text-n-slate-11">
          {{ copy.description }}
        </p>
      </div>

      <form v-if="!installation" class="space-y-4" @submit.prevent="connect">
        <label class="block">
          <span class="mb-1 block text-sm font-medium text-n-slate-12">
            {{ copy.server }}
          </span>
          <input
            v-model="serverUrl"
            type="url"
            autocomplete="url"
            required
            class="h-11 w-full rounded-lg border border-n-weak bg-n-alpha-2 px-3 text-n-slate-12 outline-none focus:border-n-brand"
          />
        </label>

        <p v-if="errorMessage" role="alert" class="text-sm text-n-ruby-11">
          {{ errorMessage }}
        </p>

        <button
          type="submit"
          :disabled="isConnecting"
          class="h-11 w-full rounded-lg bg-n-brand px-4 font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
        >
          {{ isConnecting ? copy.connecting : copy.connect }}
        </button>
      </form>

      <div
        v-if="installation"
        class="mt-6 rounded-lg border border-n-weak bg-n-alpha-1 p-4"
      >
        <p class="font-medium text-n-slate-12">
          {{ installation.instanceName }}
        </p>
        <p class="mt-1 break-all text-xs text-n-slate-10">
          {{ installation.baseUrl }}
        </p>
        <p class="mt-3 text-sm text-n-teal-11">
          {{ copy.connected }}
        </p>
      </div>

      <form v-if="installation" class="mt-6 space-y-4" @submit.prevent="signIn">
        <label class="block">
          <span class="mb-1 block text-sm font-medium text-n-slate-12">
            {{ copy.email }}
          </span>
          <input
            v-model.trim="credentials.email"
            type="email"
            autocomplete="email"
            required
            class="h-11 w-full rounded-lg border border-n-weak bg-n-alpha-2 px-3 text-n-slate-12 outline-none focus:border-n-brand"
          />
        </label>

        <label class="block">
          <span class="mb-1 block text-sm font-medium text-n-slate-12">
            {{ copy.password }}
          </span>
          <input
            v-model="credentials.password"
            type="password"
            autocomplete="current-password"
            required
            class="h-11 w-full rounded-lg border border-n-weak bg-n-alpha-2 px-3 text-n-slate-12 outline-none focus:border-n-brand"
          />
        </label>

        <p v-if="errorMessage" role="alert" class="text-sm text-n-ruby-11">
          {{ errorMessage }}
        </p>

        <button
          type="submit"
          :disabled="isLoggingIn"
          class="h-11 w-full rounded-lg bg-n-brand px-4 font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
        >
          {{ isLoggingIn ? copy.loggingIn : copy.login }}
        </button>

        <button
          type="button"
          class="h-10 w-full rounded-lg text-sm font-medium text-n-slate-11 hover:bg-n-alpha-2"
          @click="changeServer"
        >
          {{ copy.changeServer }}
        </button>
      </form>

      <p class="mt-6 text-center text-xs text-n-slate-9">
        {{ copy.runtime }} {{ runtime.platform }}
      </p>
    </section>
  </main>
</template>
