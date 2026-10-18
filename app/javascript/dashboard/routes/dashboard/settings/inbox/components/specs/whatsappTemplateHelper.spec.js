import {
  newTemplateDraft,
  validateTemplate,
  templatePayload,
  previewTemplate,
  templateError,
  matchesTemplate,
} from '../whatsappTemplateHelper';

describe('Meta template creation validation', () => {
  let draft;
  beforeEach(() => {
    draft = {
      ...newTemplateDraft(),
      name: 'order_update',
      body: 'Hello {{1}}',
      examples: ['Ada'],
    };
  });

  it('builds a positional payload and substitutes examples without interpreting markup', () => {
    draft.examples = ['<img src=x>', 'unused'];
    expect(validateTemplate(draft)).toEqual([]);
    expect(templatePayload(draft).examples).toEqual(['<img src=x>']);
    expect(previewTemplate(draft)).toBe('Hello <img src=x>');
  });

  it.each([
    'Hello {{2}}',
    'Hello {{2}} {{1}}',
    'Hello {{name}}',
    'Hello {{0}}',
    'Hello {{01}}',
    'Hello {{1}',
    'Hello {{{1}}}',
  ])('rejects nonpositional or malformed variables: %s', body => {
    draft.body = body;
    expect(validateTemplate(draft)).toContain('VARIABLES');
  });

  it('requires every example and rejects whitespace', () => {
    draft.body = '{{1}} / {{2}}';
    draft.examples = ['Ada', ' '];
    expect(validateTemplate(draft)).toContain('EXAMPLES');
  });

  it('rejects examples longer than 1024 characters', () => {
    draft.examples = ['a'.repeat(1025)];
    expect(validateTemplate(draft)).toContain('EXAMPLES');
  });

  it.each([
    'https://user:password@example.com',
    'https://example.com/a b',
    `https://example.com/${'a'.repeat(2000)}`,
  ])('rejects URL credentials, whitespace and oversized URLs: %s', url => {
    draft.buttons = [{ type: 'URL', text: 'Open', url }];
    expect(validateTemplate(draft)).toContain('BUTTONS');
  });

  it.each([
    ['name', 'Uppercase', 'NAME'],
    ['name', 'a'.repeat(513), 'NAME'],
    ['body', 'a'.repeat(1025), 'BODY'],
    ['header', 'a'.repeat(61), 'HEADER'],
    ['footer', '{{1}}', 'FOOTER'],
    ['header', '{{1}}', 'HEADER'],
    ['category', 'AUTHENTICATION', 'CATEGORY'],
    ['language', 'de', 'LANGUAGE'],
  ])('validates %s', (field, value, code) => {
    draft[field] = value;
    expect(validateTemplate(draft)).toContain(code);
  });

  it('accepts boundary lengths', () => {
    Object.assign(draft, {
      name: 'a'.repeat(512),
      body: 'a'.repeat(1024),
      header: 'a'.repeat(60),
      footer: 'a'.repeat(60),
    });
    expect(validateTemplate(draft)).toEqual([]);
  });

  it.each(
    [
      [{ type: 'URL', text: 'Open', url: 'http://example.com' }],
      [{ type: 'URL', text: 'Open', url: 'https://example.com/{{1}}' }],
      [{ type: 'URL', text: 'Open', url: 'https://example.com/%7B%7B1%7D%7D' }],
      [
        { type: 'URL', text: 'Open', url: 'https://example.com' },
        { type: 'QUICK_REPLY', text: 'OK' },
      ],
      Array.from({ length: 4 }, () => ({ type: 'QUICK_REPLY', text: 'OK' })),
      Array.from({ length: 3 }, () => ({
        type: 'URL',
        text: 'Open',
        url: 'https://example.com',
      })),
      [{ type: 'QUICK_REPLY', text: '{{1}}' }],
    ].map(buttons => [buttons])
  )('rejects invalid buttons %#', buttons => {
    draft.buttons = buttons;
    expect(validateTemplate(draft)).toContain('BUTTONS');
  });

  it('accepts static HTTPS buttons and strips stale URL fields from quick replies', () => {
    draft.buttons = [{ type: 'URL', text: 'Open', url: 'https://example.com' }];
    expect(validateTemplate(draft)).toEqual([]);
    draft.buttons = [{ type: 'QUICK_REPLY', text: 'OK', url: 'stale' }];
    expect(templatePayload(draft).buttons).toEqual([
      { type: 'QUICK_REPLY', text: 'OK' },
    ]);
  });

  it('only reconciles the matching identity AND content', () => {
    const template = {
      id: '123',
      name: draft.name,
      language: draft.language,
      category: draft.category,
      components: [{ type: 'BODY', text: draft.body }],
    };
    expect(matchesTemplate(template, draft)).toBe(true);
    expect(
      matchesTemplate(
        { ...template, components: [{ type: 'BODY', text: 'different' }] },
        draft
      )
    ).toBe(false);
    expect(matchesTemplate({ ...template, language: 'en_US' }, draft)).toBe(
      false
    );
  });

  it('treats network failures as uncertain only when creating', () => {
    expect(templateError(new Error('network'), true)).toBe('outcome_unknown');
    expect(templateError(new Error('network'))).toBe('load_failed');
  });

  it('distinguishes local access errors from Meta authentication and permission failures', () => {
    expect(templateError({ response: { status: 401 } }, true)).toBe(
      'access_denied'
    );
    expect(templateError({ response: { status: 403 } }, true)).toBe(
      'access_denied'
    );
    expect(
      templateError(
        {
          response: { status: 422, data: { error: 'authentication_required' } },
        },
        true
      )
    ).toBe('authentication_required');
    expect(
      templateError(
        { response: { status: 422, data: { error: 'permission_denied' } } },
        true
      )
    ).toBe('permission_denied');
  });

  it('can reconcile a template whose category Meta changed during review', () => {
    const template = {
      id: '123',
      name: draft.name,
      language: draft.language,
      category: 'MARKETING',
      components: [{ type: 'BODY', text: draft.body }],
    };
    expect(matchesTemplate(template, draft)).toBe(true);
  });
});
