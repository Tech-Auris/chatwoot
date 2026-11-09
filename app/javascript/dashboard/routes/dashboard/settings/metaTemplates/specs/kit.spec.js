import { isFollowUpTemplate, pendingPlaceholders } from '../kit';

describe('kit', () => {
  it('recognizes the follow-up templates', () => {
    expect(isFollowUpTemplate('auris_fup_geral2')).toBe(true);
    expect(isFollowUpTemplate('lembrete_24h')).toBe(false);
    expect(isFollowUpTemplate(undefined)).toBe(false);
  });

  it('lists the clinic data still to fill, once each', () => {
    expect(
      pendingPlaceholders(
        'Local: [endereço da clínica]. [endereço da clínica] [outra coisa]'
      )
    ).toEqual(['[endereço da clínica]']);
    expect(pendingPlaceholders('Olá {{nome}}')).toEqual([]);
  });
});
