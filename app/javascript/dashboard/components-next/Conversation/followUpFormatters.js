// "4h", "1d 6h", "2h30min": the waiting time before a FUP, as the team reads it.
export const delayLabel = minutes => {
  const days = Math.floor(minutes / 1440);
  const hours = Math.floor((minutes % 1440) / 60);
  const rest = minutes % 60;
  if (days) return hours ? `${days}d ${hours}h` : `${days}d`;
  if (hours) return rest ? `${hours}h${rest}min` : `${hours}h`;
  return `${rest}min`;
};
