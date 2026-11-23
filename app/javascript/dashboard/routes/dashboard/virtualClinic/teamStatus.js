// Each AI teammate shows its "faces", each one on or off on its own:
// - attendance (only Clara): serving patients through the n8n secretary,
//   paid by us, from the live status. The Clínica virtual only reads it;
// - assistant: talking to the teammate here, which needs the AI assistant
//   (MCP) and the clinic's OpenAI key. One key for the whole AI team, so this
//   face is the same for every teammate (`aiTeam.chat_enabled`).
// Who can't talk to the team (agents) only sees Clara's attendance.
const REASONS = {
  ai_not_found: 'AI_NOT_FOUND',
  openai_key: 'MISSING_OPENAI',
  mcp: 'MISSING_MCP',
};

const attendance = status => ({
  key: 'attendance',
  on: status?.secretary?.on_duty !== false,
  reason: status?.secretary?.off_duty_reason || null,
});

const assistant = aiTeam => ({
  key: 'assistant',
  on: aiTeam?.chat_enabled === true,
  reason: aiTeam?.chat_missing || null,
});

export const faces = (persona, status, aiTeam) => [
  ...(persona === 'secretary' ? [attendance(status)] : []),
  ...(aiTeam?.manages_team ? [assistant(aiTeam)] : []),
];

// Faded only when every face of the teammate is off.
export const isFaded = (persona, status, aiTeam) => {
  const list = faces(persona, status, aiTeam);
  return list.length > 0 && list.every(face => !face.on);
};

const detail = (face, status, t) => {
  if (!face.on) {
    return REASONS[face.reason]
      ? t(`VIRTUAL_CLINIC.FACES.REASONS.${REASONS[face.reason]}`)
      : face.reason;
  }
  // The green dot already says the assistant is on.
  if (face.key === 'assistant') return '';
  const { active_conversations: active, in_follow_up: followUps } =
    status?.secretary || {};
  return active || followUps
    ? t('VIRTUAL_CLINIC.FACES.SERVING', { active, followUps })
    : t('VIRTUAL_CLINIC.FACES.IDLE');
};

// "Atendimento · atendendo 3 · 1 em follow-up", "Assistente"…
// The attendance line waits for the live status.
export const faceLines = (persona, status, aiTeam, t) =>
  faces(persona, status, aiTeam)
    .filter(face => face.key !== 'attendance' || status?.secretary)
    .map(face => {
      const label = t(`VIRTUAL_CLINIC.FACES.${face.key.toUpperCase()}`);
      const text = detail(face, status, t);
      return {
        key: face.key,
        on: face.on,
        text: text ? `${label} · ${text}` : label,
      };
    });

// Money in the marketing teammate's status (R$ 85,40).
export const formatReais = value =>
  value.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
