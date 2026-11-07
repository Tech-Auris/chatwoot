// Meta only accepts lowercase letters, digits and underscores in a template
// name. Convert as the user types: "Confirmação de Agenda" → "confirmacao_de_agenda".
export const toTemplateName = value =>
  value
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[\s-]+/g, '_')
    .replace(/[^a-z0-9_]/g, '');
