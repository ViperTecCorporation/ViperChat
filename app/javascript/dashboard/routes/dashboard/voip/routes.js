import { frontendURL } from 'dashboard/helper/URLHelper';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/calls/:callId?'),
    name: 'agent_voip_calls',
    meta: { permissions: ['administrator', 'agent', 'custom_role'] },
    component: () => import('./CallsPage.vue'),
  },
  {
    path: frontendURL('accounts/:accountId/settings/voip'),
    name: 'agent_voip_services',
    meta: { permissions: ['administrator'] },
    component: () => import('./ServicesPage.vue'),
  },
];
