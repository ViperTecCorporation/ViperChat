/* eslint-disable no-console, no-restricted-syntax, no-await-in-loop */
/**
 * Kanban Configuration Helper
 * Natively serializes and stores Kanban configs in the description of the `_kanban_config` Label.
 */

const CONFIG_PREFIX = '[KANBAN_CONFIG]';
const CONFIG_LABEL_TITLE = 'kanban_config';

const DEFAULT_PIPELINE = {
  id: 1,
  name: 'Vendas',
  description:
    'Acompanhe seus leads de vendas desde o contato inicial até o fechamento do negócio.',
  stages: [
    { id: 'stage_1', title: 'Novo Lead', color: '#3b82f6' },
    { id: 'stage_2', title: 'Qualificando', color: '#f59e0b' },
    { id: 'stage_3', title: 'Proposta Enviada', color: '#8b5cf6' },
    { id: 'stage_4', title: 'Negociação', color: '#f97316' },
    {
      id: 'stage_5',
      title: 'Oportunidade Perdida',
      color: '#ef4444',
      is_lost: true,
    },
    {
      id: 'stage_6',
      title: 'Oportunidade Ganha',
      color: '#10b981',
      is_won: true,
    },
  ],
  inboxes: [],
  agents: [],
  automations: {
    auto_create: false,
    auto_assign_agent: false,
    auto_assign_conversation: false,
    auto_resolve_on_won_lost: false,
    auto_win_on_resolve: false,
  },
};

export const KanbanConfigHelper = {
  /**
   * Retrieves the raw config label from store
   */
  getConfigLabel(store) {
    const labels = store.getters['labels/getLabels'] || [];
    return labels.find(l => l.title === CONFIG_LABEL_TITLE);
  },

  /**
   * Loads configurations, creating the special label if absent
   */
  async loadConfig(store) {
    // Ensure labels are loaded first
    await store.dispatch('labels/get');
    let configLabel = this.getConfigLabel(store);

    if (!configLabel) {
      // Create special label with default config
      const initialPayload = {
        pipelines: [DEFAULT_PIPELINE],
      };

      await store.dispatch('labels/create', {
        title: CONFIG_LABEL_TITLE,
        description: `${CONFIG_PREFIX}${JSON.stringify(initialPayload)}`,
        color: '#1e293b',
        show_on_sidebar: false,
      });

      // Re-fetch labels
      await store.dispatch('labels/get');
      configLabel = this.getConfigLabel(store);
    }

    try {
      const desc = configLabel.description || '';
      if (desc.startsWith(CONFIG_PREFIX)) {
        const jsonStr = desc.substring(CONFIG_PREFIX.length);
        const parsed = JSON.parse(jsonStr);
        if (parsed && Array.isArray(parsed.pipelines)) {
          // Double check if pipelines array is empty, populate with default
          if (parsed.pipelines.length === 0) {
            parsed.pipelines.push(DEFAULT_PIPELINE);
          }
          return { labelId: configLabel.id, config: parsed };
        }
      }
    } catch (e) {
      console.error('Error parsing kanban config:', e);
    }

    // Return fallback with default pipeline
    return {
      labelId: configLabel ? configLabel.id : null,
      config: { pipelines: [DEFAULT_PIPELINE] },
    };
  },

  /**
   * Saves configurations to the special label
   */
  async saveConfig(store, labelId, config) {
    if (!labelId) {
      const configLabel = this.getConfigLabel(store);
      if (configLabel) {
        labelId = configLabel.id;
      } else {
        await this.loadConfig(store);
        const refetched = this.getConfigLabel(store);
        if (refetched) labelId = refetched.id;
      }
    }

    if (!labelId) {
      throw new Error('Cannot save config: _kanban_config label not found');
    }

    const newDescription = `${CONFIG_PREFIX}${JSON.stringify(config)}`;
    await store.dispatch('labels/update', {
      id: labelId,
      title: CONFIG_LABEL_TITLE,
      description: newDescription,
      color: '#1e293b',
      show_on_sidebar: false,
    });
  },
};
