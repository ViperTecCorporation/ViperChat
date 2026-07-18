module AccountSettingsSchema
  extend ActiveSupport::Concern

  CAPTAIN_MODEL_PROPERTIES = Llm::Models.feature_keys.index_with { { 'type': %w[string null] } }.freeze
  CAPTAIN_FEATURE_PROPERTIES = Llm::Models.feature_keys.index_with { { 'type': %w[boolean null] } }.freeze

  SETTINGS_PARAMS_SCHEMA = {
    'type': 'object',
    'properties':
      {
        'auto_resolve_after': { 'type': %w[integer null], 'minimum': 10, 'maximum': 1_439_856 },
        'auto_resolve_message': { 'type': %w[string null] },
        'auto_resolve_ignore_waiting': { 'type': %w[boolean null] },
        'auto_resolve_inboxes': {
          'type': %w[array null],
          'items': {
            'type': 'object',
            'properties': {
              'inbox_id': { 'type': %w[integer string] },
              'send_to_groups': { 'type': %w[boolean null] }
            },
            'required': %w[inbox_id],
            'additionalProperties': false
          }
        },
        'audio_transcriptions': { 'type': %w[boolean null] },
        'show_deleted_message_content': { 'type': %w[boolean null] },
        'auto_resolve_label': { 'type': %w[string null] },
        'keep_pending_on_bot_failure': { 'type': %w[boolean null] },
        'captain_auto_resolve_mode': { 'type': %w[string null], 'enum': ['evaluated', 'legacy', 'disabled', nil] },
        'captain_false_promise_harness_enabled': { 'type': %w[boolean null] },
        'conversation_required_attributes': {
          'type': %w[array null],
          'items': {
            'oneOf': [
              { 'type': 'string' },
              {
                'type': 'object',
                'properties': {
                  'attribute_key': { 'type': 'string' },
                  'inbox_id': { 'type': %w[integer string] },
                  'apply_to_groups': { 'type': %w[boolean null] }
                },
                'required': %w[attribute_key inbox_id],
                'additionalProperties': false
              }
            ]
          }
        },
        'captain_models': {
          'type': %w[object null],
          'properties': CAPTAIN_MODEL_PROPERTIES,
          'additionalProperties': false
        },
        'captain_features': {
          'type': %w[object null],
          'properties': CAPTAIN_FEATURE_PROPERTIES,
          'additionalProperties': false
        }
      },
    'required': [],
    'additionalProperties': true
  }.to_json.freeze
end
