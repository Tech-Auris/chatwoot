// ClickUp team id is fixed for the Auris workspace (see FieldMap::TEAM_ID
// on the backend). We assemble the task URL client-side so the admin link
// stays available even for older tickets whose sync response landed the
// task id but not the URL (a state PR1 briefly allowed).
const CLICKUP_TEAM_ID = '90132001451';

export const clickupTaskUrl = ticket => {
  if (ticket?.clickup_task_url) return ticket.clickup_task_url;
  if (!ticket?.clickup_task_id) return null;
  return `https://app.clickup.com/t/${CLICKUP_TEAM_ID}/${ticket.clickup_task_id}`;
};
