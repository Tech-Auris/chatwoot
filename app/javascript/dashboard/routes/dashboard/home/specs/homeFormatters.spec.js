import {
  bucketLabel,
  formatDuration,
  sparklinePath,
  variation,
} from '../homeFormatters';

describe('homeFormatters', () => {
  it('compares a period with the one before it', () => {
    expect(variation(142, 127)).toBe(12);
    expect(variation(6, 8)).toBe(-25);
    expect(variation(5, 0)).toBeNull();
  });

  it('formats the first response time', () => {
    expect(formatDuration(100)).toBe('1 min 40 s');
    expect(formatDuration(360)).toBe('6 min');
    expect(formatDuration(12)).toBe('12 s');
    expect(formatDuration(3900)).toBe('1 h 5 min');
    expect(formatDuration(null)).toBe('—');
  });

  it('draws the trend line across the whole box', () => {
    const path = sparklinePath([1, 3, 2], 100, 30);

    expect(path.startsWith('M0.0,27.0')).toBe(true);
    expect(path).toContain('L50.0,3.0');
    expect(path.endsWith('L100.0,15.0')).toBe(true);
  });

  it('keeps a flat or single-point series in the middle', () => {
    expect(sparklinePath([4], 100, 30)).toBe('M0.0,15.0 L100.0,15.0');
  });

  it('names what each point of the trend line covers', () => {
    const monday = new Date(2026, 10, 2).getTime() / 1000;
    const nextMonday = new Date(2026, 10, 9).getTime() / 1000;

    expect(bucketLabel(monday, null, 'day', 'pt-BR')).toMatch(/seg.*02\/11/);
    expect(bucketLabel(monday, nextMonday, 'week', 'pt-BR')).toBe(
      '02/11 – 08/11'
    );
    expect(bucketLabel(monday, null, 'month', 'pt-BR')).toMatch(/nov.*2026/);
    // The app hands its locale with an underscore.
    expect(bucketLabel(monday, null, 'day', 'pt_BR')).toMatch(/seg.*02\/11/);
  });
});
