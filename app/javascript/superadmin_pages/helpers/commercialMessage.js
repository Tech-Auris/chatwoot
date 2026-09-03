// The message the sales team pastes into WhatsApp when handing the
// proposal link to the prospect. Shared by the Quotes screen (right
// after saving the proposal) and the Reservations screen (any time
// the seller needs to re-send the link).
//
// The `data_da_reserva` slot is filled with the reservation deadline
// formatted in pt-BR. `available?` gates the copy button — the last
// sentence about "sua condição comercial ficará reservada até X" only
// makes sense when there is an X.

const formatReservedUntil = value => {
  if (!value) return '';
  try {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    const day = String(date.getDate()).padStart(2, '0');
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const year = date.getFullYear();
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    return `${day}/${month}/${year} às ${hours}:${minutes}`;
  } catch {
    return '';
  }
};

export const isReservationMessageAvailable = quote =>
  Boolean(quote?.public_url && quote?.access_code && quote?.reserved_until);

export const buildReservationMessage = quote => {
  if (!isReservationMessageAvailable(quote)) return '';

  const link = quote.public_url;
  const code = quote.access_code;
  const deadline = formatReservedUntil(quote.reserved_until);

  return (
    'Olá! 😊\n\n' +
    'Conforme alinhado em nossa reunião, você tem uma *condição especial de contratação da Auris com 10% de desconto*.\n\n' +
    'Para *reservar essa condição*, é necessário realizar a reserva pelo link abaixo, informar o *código de acesso* e preencher os dados solicitados:\n\n' +
    `*Link para reserva:* ${link}\n` +
    `*Código de acesso:* ${code}\n\n` +
    `Após o preenchimento, sua condição comercial ficará reservada até *${deadline}*.\n\n` +
    'Se tiver qualquer dúvida durante o preenchimento, pode me chamar por aqui. 💙'
  );
};
