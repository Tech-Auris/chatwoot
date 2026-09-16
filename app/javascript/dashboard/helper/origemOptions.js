// Fixed vocabulary for the "Origem do lead" attribute.
//
// Kept in one file so the sidebar dropdown, the funnel filters (Quadro / Lista /
// Visão geral / Conversão), the conversation filter, the automation rules and
// the Origem overview report all render the same choices. Mirrors
// Contacts::OriginAttributionService::OPTIONS on the backend.
export const ORIGEM_OPTIONS = [
  'Evento',
  'Facebook',
  'Google',
  'Indicação de cliente',
  'Indicação de colega',
  'Influenciador',
  'Instagram',
  'Orgânico',
];

// Sent to the backend to select conversations/contacts with no origem
// attributed at all (auto or manual). Lexically distinct from any operator-
// facing label so a future real origin named "none" can't collide.
export const ORIGEM_NONE_TOKEN = '__none__';
