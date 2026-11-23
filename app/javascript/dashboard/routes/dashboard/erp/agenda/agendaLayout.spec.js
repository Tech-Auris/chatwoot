import { layoutColumn, hourRange, spanOf } from './agendaLayout';

const at = (time, end) => ({
  starts_at: `2026-11-24T${time}:00`,
  ends_at: end ? `2026-11-24T${end}:00` : null,
});

describe('agendaLayout', () => {
  it('defaults to 30 minutes when the appointment has no end', () => {
    expect(spanOf(at('09:00'))).toEqual({ start: 540, end: 570 });
  });

  it('keeps a minimum height for very short appointments', () => {
    expect(spanOf(at('09:00', '09:05'))).toEqual({ start: 540, end: 555 });
  });

  it('puts appointments that do not overlap in a single lane', () => {
    const placed = layoutColumn([at('10:00', '10:30'), at('09:00', '10:00')]);
    expect(placed.map(p => [p.start, p.lane, p.lanes])).toEqual([
      [540, 0, 1],
      [600, 0, 1],
    ]);
  });

  it('splits overlapping appointments into lanes and reuses freed lanes', () => {
    const placed = layoutColumn([
      at('09:00', '10:00'),
      at('09:15', '09:45'),
      at('09:45', '10:15'),
      at('11:00', '11:30'),
    ]);
    expect(placed.map(p => [p.start, p.lane, p.lanes])).toEqual([
      [540, 0, 2],
      [555, 1, 2],
      [585, 1, 2],
      [660, 0, 1],
    ]);
  });

  it('shows business hours, stretched to fit early and late appointments', () => {
    expect(hourRange([])).toEqual({ start: 8, end: 18 });
    expect(hourRange([at('06:30', '07:00'), at('19:00', '19:40')])).toEqual({
      start: 6,
      end: 20,
    });
  });
});
