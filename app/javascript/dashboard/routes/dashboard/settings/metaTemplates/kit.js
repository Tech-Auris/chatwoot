// Auris kit rules shared by the kit tab and the template form. The catalog
// itself comes from the API (config/meta_template_kit.yml).

export const KIT_GROUPS = ['follow_up', 'system', 'suggested'];

// System templates are sent by the Auris engine by name, so everything but
// the body text stays as the kit defines it.
export const SYSTEM_LOCKED_FIELDS = [
  'name',
  'language',
  'category',
  'header',
  'footer',
  'buttons',
];

// Follow-up templates are installed and maintained by the kit.
export const isFollowUpTemplate = name => /^auris_fup_/.test(name || '');

// Clinic data the kit could not fill (e.g. there is no address on the
// account yet). They would go to Meta as literal text.
const PLACEHOLDER_REGEX =
  /\[(nome da clínica|horário de funcionamento|endereço da clínica)\]/g;

export const pendingPlaceholders = text => [
  ...new Set([...(text || '').matchAll(PLACEHOLDER_REGEX)].map(m => m[0])),
];

export const bodyText = template =>
  (template.components || []).find(c => (c.type || '').toUpperCase() === 'BODY')
    ?.text || '';
