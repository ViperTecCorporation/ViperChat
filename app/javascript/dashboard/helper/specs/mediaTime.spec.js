import { formatMediaTime } from '../mediaProfiles';

describe('media trim time labels', () => {
  it.each([
    [0, '00:00'],
    [123.4, '02:03'],
    [659.2, '10:59'],
    [3599.9, '59:59'],
    [3600, '60:00'],
    [NaN, '00:00'],
  ])(
    'formats %s seconds as %s without rounding the cut forward',
    (seconds, label) => {
      expect(formatMediaTime(seconds)).toBe(label);
    }
  );
});
