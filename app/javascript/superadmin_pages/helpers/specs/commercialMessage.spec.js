import { buildReservationMessage } from '../commercialMessage';

const quote = summary => ({
  public_url: 'https://app.example.com/proposals/abc',
  access_code: '123456',
  reserved_until: '2026-11-20T23:59:59-03:00',
  discount_summary: summary,
});

describe('buildReservationMessage', () => {
  it('lists the discounts the proposal carries', () => {
    expect(
      buildReservationMessage(
        quote('isenção implantação + 10% reunião + 5% indicação')
      )
    ).toContain(
      '*condição especial de contratação da Auris* (isenção implantação, 10% reunião e 5% indicação).'
    );
  });

  it('does not mention a discount the proposal does not have', () => {
    const message = buildReservationMessage(quote(null));

    expect(message).toContain('*condição especial de contratação da Auris*.');
    expect(message).not.toContain('desconto');
  });
});
