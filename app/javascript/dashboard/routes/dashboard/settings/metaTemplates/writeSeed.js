// Small session-scoped bridge between the write pages (New/Edit) and
// Index. After a successful create or update, the backend returns the
// fresh templates list — the operator is then redirected to Index,
// which used to always do its own fetch. When the write's persist
// step and the fetch's read step disagree (Meta list is eventually
// consistent, or something on the write path silently fails after the
// row has been persisted on Meta), the operator lands back on Index
// without the change they just made and has to hit Sincronizar to see
// it. Seeding Index from the actual response of the write we just
// made bypasses that whole class of race — we already have the data,
// no need to trust that the next GET will see it.
//
// Only lives for the next Index mount within ~10 seconds of the write.
// Beyond that we assume the operator navigated elsewhere and the seed
// is stale; Index does a normal fetch.

const KEY = 'meta_templates:write_seed';
const MAX_AGE_MS = 10_000;

export const stashWriteSeed = ({ inboxId, templates, lastSyncedAt }) => {
  try {
    sessionStorage.setItem(
      KEY,
      JSON.stringify({
        inboxId,
        templates: templates || [],
        lastSyncedAt: lastSyncedAt || null,
        stashedAt: Date.now(),
      })
    );
  } catch (_e) {
    // Storage quota / private mode — the fetch fallback still works.
  }
};

export const takeWriteSeed = inboxId => {
  try {
    const raw = sessionStorage.getItem(KEY);
    if (!raw) return null;
    sessionStorage.removeItem(KEY);
    const parsed = JSON.parse(raw);
    if (!parsed) return null;
    if (Number(parsed.inboxId) !== Number(inboxId)) return null;
    if (Date.now() - parsed.stashedAt > MAX_AGE_MS) return null;
    return { templates: parsed.templates, lastSyncedAt: parsed.lastSyncedAt };
  } catch (_e) {
    return null;
  }
};
