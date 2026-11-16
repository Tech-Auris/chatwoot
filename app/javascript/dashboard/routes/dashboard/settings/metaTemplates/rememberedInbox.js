// The inbox picked on the Templates Meta list, remembered per account in
// this browser. The list reopens on it (also after a reload), and New/Edit
// store the inbox they wrote to so the list comes back on that one.
const key = accountId => `metaTemplates.inbox.${accountId}`;

export const rememberInbox = (accountId, inboxId) => {
  try {
    localStorage.setItem(key(accountId), String(inboxId));
  } catch (_e) {
    // Private mode / blocked storage: the list falls back to the first inbox.
  }
};

export const rememberedInbox = accountId => {
  try {
    return Number(localStorage.getItem(key(accountId))) || null;
  } catch (_e) {
    return null;
  }
};
