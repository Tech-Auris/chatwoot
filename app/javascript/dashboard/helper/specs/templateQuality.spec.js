import {
  templateQualityKey,
  templateScore,
  templateQualityWarns,
  templateQualityBlocksCampaign,
  templateQualityDate,
} from '../templateQuality';

describe('templateQuality', () => {
  const template = (score, status = 'APPROVED') => ({
    status,
    quality_score: score ? { score, date: 1_700_000_000 } : undefined,
  });

  it('reads the score, with no rating yet as UNKNOWN', () => {
    expect(templateScore(template('YELLOW'))).toBe('YELLOW');
    expect(templateScore(template(undefined))).toBe('UNKNOWN');
  });

  it('lets a paused or disabled template win over its score', () => {
    expect(templateQualityKey(template('RED', 'PAUSED'))).toBe('PAUSED');
    expect(templateQualityKey(template('GREEN', 'DISABLED'))).toBe('DISABLED');
    expect(templateQualityKey(template('GREEN'))).toBe('GREEN');
  });

  it('warns from Média down and blocks campaigns from Baixa down', () => {
    expect(templateQualityWarns('UNKNOWN')).toBe(false);
    expect(templateQualityWarns('YELLOW')).toBe(true);
    expect(templateQualityBlocksCampaign('YELLOW')).toBe(false);
    expect(templateQualityBlocksCampaign('RED')).toBe(true);
    expect(templateQualityBlocksCampaign('PAUSED')).toBe(true);
  });

  it('reads the evaluation date from seconds', () => {
    expect(templateQualityDate(template('GREEN'))).toEqual(
      new Date(1_700_000_000_000)
    );
  });
});
