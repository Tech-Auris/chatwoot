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
    return `${day}/${month}/${year}`;
  } catch {
    return '';
  }
};

// " (10% reunião, 5% indicação e isenção implantação)" — the discounts the
// proposal carries, read from its summary; empty when there are none.
const discountsClause = summary => {
  const parts = (summary || '').split(' + ').filter(Boolean);
  if (!parts.length) return '';
  const sentence =
    parts.length === 1
      ? parts[0]
      : `${parts.slice(0, -1).join(', ')} e ${parts[parts.length - 1]}`;
  return ` (${sentence})`;
};

export const isReservationMessageAvailable = quote =>
  Boolean(quote?.public_url && quote?.access_code && quote?.reserved_until);

// "Olá, Fernanda. Por aqui é o Gustavo da Auris." — first names of the lead
// and of the seller who made the proposal.
const greeting = quote => {
  const lead = (quote.contact_name || '').split(' ')[0];
  const seller = (quote.seller_name || '').split(' ')[0];
  const hello = lead ? `Olá, ${lead}.` : 'Olá!';
  return `${hello} Por aqui é o ${seller} da Auris.`;
};

// Two wordings: the special condition when the meeting discount was given,
// or a plain "here is your quote" otherwise — a lead without the discount
// must not learn that one exists.
export const buildReservationMessage = quote => {
  if (!isReservationMessageAvailable(quote)) return '';

  const link = quote.public_url;
  const code = quote.access_code;
  const deadline = formatReservedUntil(quote.reserved_until);

  if (!quote.meeting_discount_active) {
    return (
      `${greeting(quote)}\n\n` +
      'Segue seu orçamento. Para visualizar é necessário acessar a reserva pelo link abaixo, informar o *código de acesso* e preencher os dados solicitados:\n\n' +
      `*Link para reserva:* ${link}\n` +
      `*Código de acesso:* ${code}\n\n` +
      'Se tiver qualquer dúvida durante o preenchimento, pode me chamar por aqui. 💙'
    );
  }

  return (
    `${greeting(quote)}\n\n` +
    `Conforme alinhado em nossa reunião, você tem uma *condição especial de contratação da Auris*${discountsClause(quote.discount_summary)}.\n\n` +
    'Para *reservar essa condição*, é necessário realizar a reserva pelo link abaixo, informar o *código de acesso* e preencher os dados solicitados:\n\n' +
    `*Link para reserva:* ${link}\n` +
    `*Código de acesso:* ${code}\n\n` +
    `Após o preenchimento, sua condição comercial ficará reservada até *${deadline}*.\n\n` +
    'Se tiver qualquer dúvida durante o preenchimento, pode me chamar por aqui. 💙'
  );
};
