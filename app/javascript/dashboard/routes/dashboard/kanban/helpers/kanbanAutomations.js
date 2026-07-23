/* eslint-disable no-console, no-restricted-syntax, no-continue, no-await-in-loop */
import { KanbanConfigHelper } from './kanbanConfig';
import ConversationApi from 'dashboard/api/conversations';

export const triggerStageTypebot = async (conversation, stage) => {
  if (!conversation || !stage) return;
  const typebotUrl = stage.typebot_url || '';
  const typebotId = stage.typebot_id || '';
  if (!typebotUrl || !typebotId) return;

  const baseUrl = typebotUrl.replace(/\/+$/, '');
  const contact = conversation.meta?.sender || {};

  try {
    const response = await fetch(
      `${baseUrl}/api/v1/typebots/${typebotId}/startChat`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          prefilledVariables: {
            name: contact.name || '',
            email: contact.email || '',
            phone_number: contact.phone_number || '',
            conversation_id: String(conversation.display_id || conversation.id),
            inbox_id: String(conversation.inbox_id || ''),
          },
        }),
      }
    );
    if (!response.ok) {
      console.error(
        `Typebot trigger failed: ${response.status} for stage ${stage.id}`,
        await response.text().catch(() => '')
      );
    }
  } catch (err) {
    console.error(`Typebot trigger error for stage ${stage.id}:`, err);
  }
};

const assignOnlineAgent = async (store, conversationId, pipeline) => {
  const agentsList = pipeline.agents || [];
  const allAgents = store.getters['agents/getAgents'] || [];
  const onlineAgents = allAgents.filter(
    a => a.availability_status === 'online'
  );
  const eligible =
    agentsList.length > 0
      ? onlineAgents.filter(a => agentsList.includes(a.id))
      : onlineAgents;
  if (eligible.length > 0) {
    const agent = eligible[Math.floor(Math.random() * eligible.length)];
    await store.dispatch('conversations/assignAgent', {
      conversationId,
      agentId: agent.id,
    });
  }
};

export const KanbanAutomations = {
  register(store) {
    const configPromise = KanbanConfigHelper.loadConfig(store);

    const getConfig = async () => {
      try {
        const result = await configPromise;
        return result.config;
      } catch (err) {
        console.error('Failed to load Kanban config for automations:', err);
        return null;
      }
    };

    const tryAutoCreate = async (conversation, config, isAgentFirstMsg) => {
      if (!conversation || !conversation.id) return;

      for (const pipeline of config.pipelines) {
        if (!pipeline.automations?.auto_create) continue;
        if (isAgentFirstMsg && pipeline.automations?.auto_create_skip_agent)
          continue;

        const stageIds = pipeline.stages.map(s => s.id);
        const hasStage =
          conversation.kanban_stage &&
          stageIds.includes(conversation.kanban_stage);

        if (!hasStage && pipeline.stages.length > 0) {
          const firstStage = pipeline.stages[0];

          // Dispara Typebot antes do update para não depender da migration
          triggerStageTypebot(conversation, firstStage);

          try {
            await ConversationApi.update(conversation.id, {
              kanban_stage: firstStage.id,
            });
            store.dispatch('updateConversation', {
              id: conversation.id,
              kanban_stage: firstStage.id,
            });

            if (
              pipeline.automations?.auto_assign_agent &&
              !conversation.meta?.assignee
            ) {
              await assignOnlineAgent(store, conversation.id, pipeline);
            }
          } catch (err) {
            console.error(
              `Automation failed: auto_create for chat #${conversation.id}`,
              err
            );
          }
        }
      }
    };

    return store.subscribe(async mutation => {
      const { type, payload } = mutation;

      const config = await getConfig();
      if (!config || !Array.isArray(config.pipelines)) return;

      if (type === 'ADD_CONVERSATION') {
        const conversation = payload;
        if (!conversation || !conversation.id) return;
        if (conversation.status === 'resolved') return;

        const firstMsg =
          conversation.last_non_activity_message || conversation.messages?.[0];
        const isAgentFirstMsg = firstMsg && firstMsg.message_type === 1;

        await tryAutoCreate(conversation, config, isAgentFirstMsg);
      }

      if (type === 'UPDATE_CONVERSATION') {
        const conversation = payload;
        if (!conversation || !conversation.id) return;
        if (conversation.status !== 'open') return;

        const alreadyInPipeline = config.pipelines.some(p =>
          p.stages.some(s => s.id === conversation.kanban_stage)
        );
        if (alreadyInPipeline) return;

        await tryAutoCreate(conversation, config);
      }

      if (type === 'CHANGE_CONVERSATION_STATUS') {
        const { conversationId, status } = payload;
        if (status !== 'resolved' || !conversationId) return;

        const conversation = store.getters.getConversationById(conversationId);
        if (!conversation) return;

        for (const pipeline of config.pipelines) {
          if (!pipeline.automations?.auto_win_on_resolve) continue;

          const currentStageId = conversation.kanban_stage;
          if (!currentStageId) continue;

          const currentStage = pipeline.stages.find(
            s => s.id === currentStageId
          );
          if (!currentStage) continue;

          const wonStage = pipeline.stages.find(s => s.is_won);
          if (wonStage && currentStageId !== wonStage.id) {
            try {
              await ConversationApi.update(conversationId, {
                kanban_stage: wonStage.id,
              });
              store.dispatch('updateConversation', {
                id: conversationId,
                kanban_stage: wonStage.id,
              });
            } catch (err) {
              console.error(
                `Automation failed: auto_win_on_resolve for chat #${conversationId}`,
                err
              );
            }
          }
        }
      }
    });
  },
};
