import { createApp } from 'vue';
import { createI18n } from 'vue-i18n';
import '../widget/assets/scss/woot.scss';
import App from '../widget/webAttendance/App.vue';
import messages from '../widget/webAttendance/i18n';
import { takeInvitation } from '../widget/webAttendance/api';

// Strip the secret before mounting or exchanging it for a session.
const invitation = takeInvitation();
const app = createApp(App, { invitation });
app.use(
  createI18n({
    legacy: false,
    locale: navigator.language.startsWith('pt') ? 'pt-BR' : 'en',
    fallbackLocale: 'en',
    messages,
  })
);
app.mount('#app');
