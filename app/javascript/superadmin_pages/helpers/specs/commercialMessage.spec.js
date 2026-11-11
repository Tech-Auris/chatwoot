import { buildReservationMessage } from '../commercialMessage';

const quote = (summary, meetingDiscountActive = true) => ({
  public_url: 'https://app.example.com/proposals/abc',
  access_code: '123456',
  reserved_until: '2026-11-20T23:59:59-03:00',
  discount_summary: summary,
  contact_name: 'Fernanda Alarcon',
  seller_name: 'Gustavo Meneghetti',
  meeting_discount_active: meetingDiscountActive,
});

describe('buildReservationMessage', () => {
  it('greets the lead and the seller by first name', () => {
    expect(buildReservationMessage(quote(null))).toMatch(
      /^Olá, Fernanda\. Por aqui é o Gustavo da Auris\./
    );
  });

  it('lists the discounts the proposal carries with the meeting discount', () => {
    expect(
      buildReservationMessage(
        quote('isenção implantação + 10% reunião + 5% indicação')
      )
    ).toContain(
      '*condição especial de contratação da Auris* (isenção implantação, 10% reunião e 5% indicação).'
    );
  });

  it('sends the quote without hinting at a special condition otherwise', () => {
    const message = buildReservationMessage(quote('5% indicação', false));

    expect(message).toContain('Segue seu orçamento.');
    expect(message).toContain('123456');
    expect(message).not.toContain('condição');
    expect(message).not.toContain('desconto');
  });
});
