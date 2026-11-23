// Two separate switches for each AI teammate:
// - serving patients (only Clara: the n8n secretary, paid with our key),
//   from the live status;
// - talking to the clinic team here, which needs the AI assistant and the
//   clinic's own OpenAI key (`aiTeam.chat_enabled`).
export const isOffDuty = (persona, status) =>
  persona === 'secretary' && status?.secretary?.on_duty === false;

export const offDutyReason = (status, t) => {
  const reason = status?.secretary?.off_duty_reason;
  return reason === 'not_set_up'
    ? t('VIRTUAL_CLINIC.STATUS.NOT_SET_UP')
    : reason;
};

// Money in the marketing teammate's status (R$ 85,40).
export const formatReais = value =>
  value.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
