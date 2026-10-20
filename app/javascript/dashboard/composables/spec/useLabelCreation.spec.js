import { ref } from 'vue';
import { useLabelCreation } from '../useLabelCreation';

const state = vi.hoisted(() => ({ account: null, role: null }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: state.account }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStoreGetters: () => ({ getCurrentRole: state.role }),
}));

describe('label creation permission', () => {
  beforeEach(() => {
    state.account = ref({ settings: {} });
    state.role = ref('agent');
  });

  it('defaults agents to denied and reacts to account changes', () => {
    const { canCreateLabels } = useLabelCreation();
    expect(canCreateLabels.value).toBe(false);
    state.account.value.settings.allow_agents_to_create_labels = true;
    expect(canCreateLabels.value).toBe(true);
    state.account.value = { settings: {} };
    expect(canCreateLabels.value).toBe(false);
  });

  it('never treats a string false as permission', () => {
    state.account.value.settings.allow_agents_to_create_labels = 'false';
    expect(useLabelCreation().canCreateLabels.value).toBe(false);
  });

  it('preserves administrator access and denies unknown roles', () => {
    state.role.value = 'administrator';
    const { canCreateLabels } = useLabelCreation();
    expect(canCreateLabels.value).toBe(true);
    state.account.value.settings.allow_agents_to_create_labels = true;
    state.role.value = 'unknown';
    expect(canCreateLabels.value).toBe(false);
  });
});
