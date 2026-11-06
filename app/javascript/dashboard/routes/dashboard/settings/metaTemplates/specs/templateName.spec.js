import { toTemplateName } from '../templateName';

describe('toTemplateName', () => {
  it('turns a free-text name into snake_case', () => {
    expect(toTemplateName('Confirmação de Agenda')).toBe(
      'confirmacao_de_agenda'
    );
  });

  it('drops accents, symbols and uppercase', () => {
    expect(toTemplateName('Lembrete-Consulta! Ç 24h')).toBe(
      'lembrete_consulta_c_24h'
    );
  });

  it('keeps a trailing underscore so the user can keep typing', () => {
    expect(toTemplateName('boas ')).toBe('boas_');
  });

  it('leaves a valid name untouched', () => {
    expect(toTemplateName('promo_black_friday_2026')).toBe(
      'promo_black_friday_2026'
    );
  });
});
