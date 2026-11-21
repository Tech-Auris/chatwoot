// Shared by the clinic pipeline card and list: how long the contact has been
// on the stage, and who or what put it in the pipeline.
export const elapsedSince = (t, epochSeconds) => {
  const seconds = Number(epochSeconds) || 0;
  if (!seconds) return '';
  const diff = Math.max(0, Math.floor(Date.now() / 1000) - seconds);
  const hours = Math.floor(diff / 3600);
  if (hours < 24) return t('FUNNEL.CARD.ELAPSED_HOURS', { hours });
  const days = Math.floor(hours / 24);
  return t('FUNNEL.CARD.ELAPSED_DAYS_HOURS', {
    days,
    hours: hours - days * 24,
  });
};

export const entryOriginLabel = (t, entry) => {
  if (entry.source === 'automatic') return t('PIPELINES.ORIGIN.AUTOMATIC');
  if (entry.added_by?.name)
    return t('PIPELINES.ORIGIN.MANUAL_BY', { name: entry.added_by.name });
  return t('PIPELINES.ORIGIN.MANUAL');
};
