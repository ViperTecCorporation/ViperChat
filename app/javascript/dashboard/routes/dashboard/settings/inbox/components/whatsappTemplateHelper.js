export const newTemplateDraft = () => ({
  name: '',
  category: 'UTILITY',
  language: 'pt_BR',
  body: '',
  header: '',
  footer: '',
  examples: [],
  buttons: [],
});

export const templateVariables = body => [
  ...new Set(
    [...body.matchAll(/\{\{([1-9]\d*)\}\}/g)].map(match => Number(match[1]))
  ),
];

const hasBraces = value => /[{}]/.test(value);
const length = value => Array.from(value).length;

export function validateTemplate(draft) {
  const errors = [];
  if (!/^[a-z0-9_]{1,512}$/.test(draft.name)) errors.push('NAME');
  if (!['MARKETING', 'UTILITY'].includes(draft.category))
    errors.push('CATEGORY');
  if (!['pt_BR', 'en_US', 'es'].includes(draft.language))
    errors.push('LANGUAGE');
  if (!draft.body.trim() || length(draft.body) > 1024) errors.push('BODY');
  const variables = templateVariables(draft.body);
  if (
    hasBraces(draft.body.replace(/\{\{[1-9]\d*\}\}/g, '')) ||
    variables.some((value, index) => value !== index + 1)
  )
    errors.push('VARIABLES');
  if (
    variables.some(
      value =>
        !draft.examples[value - 1]?.trim() ||
        length(draft.examples[value - 1]) > 1024
    )
  )
    errors.push('EXAMPLES');
  if (length(draft.header) > 60 || hasBraces(draft.header))
    errors.push('HEADER');
  if (length(draft.footer) > 60 || hasBraces(draft.footer))
    errors.push('FOOTER');
  const types = new Set(draft.buttons.map(button => button.type));
  if (
    types.size > 1 ||
    draft.buttons.length > (types.has('URL') ? 2 : 3) ||
    draft.buttons.some(button => {
      if (
        !['URL', 'QUICK_REPLY'].includes(button.type) ||
        !button.text.trim() ||
        length(button.text) > 25 ||
        hasBraces(button.text)
      )
        return true;
      if (button.type !== 'URL') return false;
      try {
        const url = new URL(button.url);
        return (
          url.protocol !== 'https:' ||
          !url.hostname ||
          !!url.username ||
          !!url.password ||
          length(button.url) > 2000 ||
          /\s/.test(button.url) ||
          hasBraces(button.url) ||
          /%7[bd]/i.test(button.url)
        );
      } catch {
        return true;
      }
    })
  )
    errors.push('BUTTONS');
  return errors;
}

export const templatePayload = draft => ({
  ...draft,
  examples: templateVariables(draft.body).map(
    value => draft.examples[value - 1]
  ),
  buttons: draft.buttons.map(button =>
    button.type === 'URL'
      ? { type: button.type, text: button.text, url: button.url }
      : { type: button.type, text: button.text }
  ),
});

export const previewTemplate = draft =>
  draft.body.replace(
    /\{\{([1-9]\d*)\}\}/g,
    (placeholder, index) => draft.examples[Number(index) - 1] || placeholder
  );

export function templateError(error, creating = false) {
  const code = error.response?.data?.error;
  const known = [
    'permission_denied',
    'authentication_required',
    'validation_failed',
    'provider_rejected',
    'temporarily_unavailable',
    'outcome_unknown',
    'configuration_missing',
    'name_conflict',
    'unsupported_provider',
  ];
  if (known.includes(code)) return code;
  if ([401, 403].includes(error.response?.status)) return 'access_denied';
  return creating ? 'outcome_unknown' : 'load_failed';
}

export function matchesTemplate(template, draft) {
  if (template.name !== draft.name || template.language !== draft.language)
    return false;
  const components = template.components || [];
  const header = components.find(component => component.type === 'HEADER');
  const componentCount =
    1 +
    Number(!!draft.header.trim()) +
    Number(!!draft.footer.trim()) +
    Number(!!draft.buttons.length);
  if (
    !template.id ||
    template.parameter_format === 'NAMED' ||
    components.length !== componentCount ||
    components.some(
      component =>
        !['HEADER', 'BODY', 'FOOTER', 'BUTTONS'].includes(component.type)
    ) ||
    (header && header.format !== 'TEXT')
  )
    return false;
  const text = type =>
    components.find(component => component.type === type)?.text || '';
  const buttons =
    components.find(component => component.type === 'BUTTONS')?.buttons || [];
  return (
    text('BODY') === draft.body &&
    text('HEADER') === draft.header &&
    text('FOOTER') === draft.footer &&
    JSON.stringify(
      buttons.map(({ type, text: label, url }) => ({
        type,
        text: label,
        ...(type === 'URL' ? { url } : {}),
      }))
    ) === JSON.stringify(templatePayload(draft).buttons)
  );
}
