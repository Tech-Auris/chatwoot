// Constants
export const DEFAULT_LANGUAGE = 'en';
export const DEFAULT_CATEGORY = 'UTILITY';
export const COMPONENT_TYPES = {
  HEADER: 'HEADER',
  BODY: 'BODY',
  FOOTER: 'FOOTER',
  BUTTONS: 'BUTTONS',
};
export const MEDIA_FORMATS = ['IMAGE', 'VIDEO', 'DOCUMENT'];

export const findComponentByType = (template, type) =>
  template.components?.find(component => component.type === type);

export const processVariable = str => {
  return str.replace(/{{|}}/g, '');
};

export const allKeysRequired = value => {
  const keys = Object.keys(value);
  return keys.every(key => value[key]);
};

// Substitute {{var}} placeholders in an arbitrary template string using
// values from a component-scoped params bag (`body`, `header`, ...).
// Unfilled placeholders survive verbatim so the operator sees where the
// gaps are.
export const replaceComponentVariables = (text, componentParams) => {
  if (!text) return '';
  return text.replace(/{{([^}]+)}}/g, (match, variable) => {
    const key = processVariable(variable);
    return componentParams?.[key] || `{{${variable}}}`;
  });
};

export const replaceTemplateVariables = (templateText, processedParams) => {
  return replaceComponentVariables(templateText, processedParams.body);
};

// Full-shape rendering used both for the operator's live preview and
// for the message content we persist in Chatwoot. Templates on Meta
// are composed of HEADER + BODY + FOOTER; the recipient sees all three
// on WhatsApp but we used to persist only the body, so the operator's
// panel showed a stripped-down message that no longer matched what the
// customer received. Join with blank lines for a plain-text render that
// mirrors WhatsApp's visual layout.
export const composeTemplateContent = (template, processedParams = {}) => {
  const headerComponent = findComponentByType(template, COMPONENT_TYPES.HEADER);
  const bodyComponent = findComponentByType(template, COMPONENT_TYPES.BODY);
  const footerComponent = findComponentByType(template, COMPONENT_TYPES.FOOTER);

  const parts = [];
  // Media headers have no text to render — the recipient sees the image/
  // video/document instead. Only include text-format headers here.
  if (
    headerComponent &&
    (headerComponent.format || 'TEXT').toUpperCase() === 'TEXT' &&
    headerComponent.text
  ) {
    parts.push(
      replaceComponentVariables(headerComponent.text, processedParams.header)
    );
  }
  if (bodyComponent?.text) {
    parts.push(
      replaceComponentVariables(bodyComponent.text, processedParams.body)
    );
  }
  if (footerComponent?.text) {
    parts.push(footerComponent.text);
  }
  return parts.join('\n\n');
};

export const buildTemplateParameters = (template, hasMediaHeaderValue) => {
  const allVariables = {};

  const bodyComponent = findComponentByType(template, COMPONENT_TYPES.BODY);
  const headerComponent = findComponentByType(template, COMPONENT_TYPES.HEADER);

  if (!bodyComponent) return allVariables;

  const templateString = bodyComponent.text;

  // Process body variables
  const matchedVariables = templateString.match(/{{([^}]+)}}/g);
  if (matchedVariables) {
    allVariables.body = {};
    matchedVariables.forEach(variable => {
      const key = processVariable(variable);
      allVariables.body[key] = '';
    });
  }

  if (hasMediaHeaderValue) {
    if (!allVariables.header) allVariables.header = {};
    // `example.header_handle` is Meta's preview URL — the one that
    // sits on `scontent.whatsapp.net`. Passing it back to their send
    // API returns 131053 ("Media upload error") because that URL is
    // not fetchable from outside; it is only intended for preview.
    // The backend now caches a real, reusable media_id from the sync
    // step and prefers that at send time, so leaving `media_url`
    // blank here is safe — the agent does not need to paste a URL
    // for a template whose header was registered on the Meta side.
    allVariables.header.media_url = '';
    allVariables.header.media_type = headerComponent.format.toLowerCase();

    // For document templates, include media_name field for filename support
    if (headerComponent.format.toLowerCase() === 'document') {
      allVariables.header.media_name = '';
    }
  }

  // TEXT headers can carry variables too (Meta allows up to one). If we
  // don't create input slots for them the operator has no way to fill
  // them in and Meta rejects the send with error 132000 ("Number of
  // parameters does not match the expected number of params"). Extract
  // any {{var}} placeholders the same way the body does.
  if (
    headerComponent &&
    (headerComponent.format || 'TEXT').toUpperCase() === 'TEXT'
  ) {
    const headerVars = headerComponent.text?.match(/{{([^}]+)}}/g);
    if (headerVars && headerVars.length > 0) {
      if (!allVariables.header) allVariables.header = {};
      headerVars.forEach(v => {
        allVariables.header[processVariable(v)] = '';
      });
    }
  }

  // Process button variables
  const buttonComponents = template.components.filter(
    component => component.type === COMPONENT_TYPES.BUTTONS
  );

  buttonComponents.forEach(buttonComponent => {
    if (buttonComponent.buttons) {
      buttonComponent.buttons.forEach((button, index) => {
        // Handle URL buttons with variables
        if (button.type === 'URL' && button.url && button.url.includes('{{')) {
          const buttonVars = button.url.match(/{{([^}]+)}}/g) || [];
          if (buttonVars.length > 0) {
            if (!allVariables.buttons) allVariables.buttons = [];
            allVariables.buttons[index] = {
              type: 'url',
              parameter: '',
              url: button.url,
              variables: buttonVars.map(v => processVariable(v)),
            };
          }
        }

        // Handle copy code buttons
        if (button.type === 'COPY_CODE') {
          if (!allVariables.buttons) allVariables.buttons = [];
          allVariables.buttons[index] = {
            type: 'copy_code',
            parameter: '',
          };
        }
      });
    }
  });

  return allVariables;
};
