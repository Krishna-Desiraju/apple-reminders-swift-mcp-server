import { describe, expect, it } from 'vitest';
import { formatRecurrenceSummary, recurrenceSummaryLine } from '../../src/tools/recurrence-summary.js';
import { isUnsupportedRecurrence } from '../../src/types/reminder.js';
import type { Reminder, UnsupportedRecurrence } from '../../src/types/reminder.js';

describe('formatRecurrenceSummary', () => {
  it.each([
    [{ frequency: 'daily', interval: 1 }, 'Every day'],
    [{ frequency: 'daily', interval: 3 }, 'Every 3 days'],
    [{ frequency: 'weekly', interval: 1 }, 'Every week'],
    [{ frequency: 'weekly', interval: 2 }, 'Every 2 weeks'],
    [{ frequency: 'weekly', interval: 1, daysOfWeek: ['monday', 'wednesday'] }, 'Every week on Mon, Wed'],
    [{ frequency: 'weekly', interval: 2, daysOfWeek: ['monday'] }, 'Every 2 weeks on Mon'],
    [{ frequency: 'monthly', interval: 1 }, 'Every month'],
    [{ frequency: 'yearly', interval: 2 }, 'Every 2 years'],
    [{ frequency: 'monthly', interval: 1, daysOfMonth: [1, 15] }, 'Every month on the 1st and 15th'],
    [{ frequency: 'monthly', interval: 1, daysOfMonth: [1, 15, 31] }, 'Every month on the 1st, 15th and 31st'],
    [{ frequency: 'monthly', interval: 1, daysOfMonth: [15] }, 'Every month on the 15th'],
    [{ frequency: 'monthly', interval: 2, daysOfMonth: [1] }, 'Every 2 months on the 1st'],
    [{ frequency: 'monthly', interval: 1, nthWeekday: { ordinal: 1, weekday: 'monday' } }, 'Every month on the first Monday'],
    [{ frequency: 'monthly', interval: 1, nthWeekday: { ordinal: 2, weekday: 'tuesday' } }, 'Every month on the second Tuesday'],
    [{ frequency: 'monthly', interval: 1, nthWeekday: { ordinal: 3, weekday: 'wednesday' } }, 'Every month on the third Wednesday'],
    [{ frequency: 'monthly', interval: 1, nthWeekday: { ordinal: 4, weekday: 'sunday' } }, 'Every month on the fourth Sunday'],
    [{ frequency: 'monthly', interval: 1, nthWeekday: { ordinal: 5, weekday: 'saturday' } }, 'Every month on the fifth Saturday'],
    [{ frequency: 'monthly', interval: 1, nthWeekday: { ordinal: -1, weekday: 'friday' } }, 'Every month on the last Friday'],
    [{ frequency: 'monthly', interval: 3, nthWeekday: { ordinal: 1, weekday: 'monday' } }, 'Every 3 months on the first Monday'],
    [{ frequency: 'yearly', interval: 1 }, 'Every year'],
    [{ frequency: 'yearly', interval: 1, monthsOfYear: [3] }, 'Every year in March'],
    [{ frequency: 'yearly', interval: 1, monthsOfYear: [3, 6] }, 'Every year in March and June'],
    [{ frequency: 'yearly', interval: 1, monthsOfYear: [9, 3, 6] }, 'Every year in March, June and September'],
    [{ frequency: 'yearly', interval: 1, monthsOfYear: [1, 12] }, 'Every year in January and December'],
    [
      { frequency: 'yearly', interval: 1, monthsOfYear: [11], nthWeekday: { ordinal: 4, weekday: 'thursday' } },
      'Every year on the fourth Thursday of November',
    ],
    [
      { frequency: 'yearly', interval: 2, monthsOfYear: [5], nthWeekday: { ordinal: -1, weekday: 'monday' } },
      'Every 2 years on the last Monday of May',
    ],
    [{ frequency: 'daily', interval: 1, endDate: '2026-12-31' }, 'Every day, until Dec 31, 2026'],
    [{ frequency: 'weekly', interval: 1, daysOfWeek: ['monday'], endDate: '2027-01-05' }, 'Every week on Mon, until Jan 5, 2027'],
    [{ frequency: 'yearly', interval: 1, monthsOfYear: [3], endDate: '2030-03-01' }, 'Every year in March, until Mar 1, 2030'],
    [{ frequency: 'daily', interval: 1, occurrenceCount: 3 }, 'Every day, 3 occurrences left'],
    [{ frequency: 'daily', interval: 1, occurrenceCount: 1 }, 'Every day, 1 occurrence left'],
    [{ frequency: 'monthly', interval: 1, daysOfMonth: [1, 15], occurrenceCount: 10 }, 'Every month on the 1st and 15th, 10 occurrences left'],
  ] as const)('%j -> %s', (rule, summary) => {
    expect(formatRecurrenceSummary(rule)).toBe(summary);
  });

  it('orders weekdays Sunday first, whatever order they come in', () => {
    expect(
      formatRecurrenceSummary({
        frequency: 'weekly',
        interval: 1,
        daysOfWeek: ['saturday', 'monday', 'sunday', 'friday', 'tuesday', 'thursday', 'wednesday'],
      })
    ).toBe('Every week on Sun, Mon, Tue, Wed, Thu, Fri, Sat');
  });

  it('drops duplicate weekdays', () => {
    expect(
      formatRecurrenceSummary({ frequency: 'weekly', interval: 1, daysOfWeek: ['friday', 'friday'] })
    ).toBe('Every week on Fri');
  });

  it.each([
    [1, '1st'], [2, '2nd'], [3, '3rd'], [4, '4th'], [10, '10th'], [11, '11th'], [12, '12th'],
    [13, '13th'], [21, '21st'], [22, '22nd'], [23, '23rd'], [30, '30th'], [31, '31st'],
  ])('writes day %i as %s', (day, text) => {
    expect(formatRecurrenceSummary({ frequency: 'monthly', interval: 1, daysOfMonth: [day] })).toBe(
      `Every month on the ${text}`
    );
  });

  it('sorts and de-duplicates days of the month', () => {
    expect(
      formatRecurrenceSummary({ frequency: 'monthly', interval: 1, daysOfMonth: [15, 1, 15] })
    ).toBe('Every month on the 1st and 15th');
  });

  it('does not shift the end date by time zone', () => {
    const original = process.env.TZ;
    try {
      for (const tz of ['Pacific/Kiritimati', 'Pacific/Pago_Pago', 'UTC']) {
        process.env.TZ = tz;
        expect(
          formatRecurrenceSummary({ frequency: 'daily', interval: 1, endDate: '2026-01-01' })
        ).toBe('Every day, until Jan 1, 2026');
      }
    } finally {
      if (original === undefined) delete process.env.TZ;
      else process.env.TZ = original;
    }
  });

  it('treats a missing interval as 1', () => {
    expect(formatRecurrenceSummary({ frequency: 'daily' } as never)).toBe('Every day');
  });
});

describe('unsupported recurrence', () => {
  const marker: UnsupportedRecurrence = { supported: false, rrule: 'FREQ=MONTHLY;INTERVAL=1;BYDAY=MO,TU;BYSETPOS=-1' };
  const reminder = (recurrence: Reminder['recurrence']): Reminder => ({
    id: 'ID-1',
    title: 'Gym',
    isCompleted: false,
    priority: 0,
    listId: 'list-1',
    listName: 'Personal',
    flagged: false,
    hasAlarms: false,
    hasRecurrenceRules: recurrence !== null,
    recurrence,
    dueDateHasTime: false,
  });

  it('summarises the marker as a custom schedule', () => {
    expect(formatRecurrenceSummary(marker)).toBe("Repeats on a custom schedule this server can't edit");
  });

  it('never puts the RRULE in the summary', () => {
    expect(formatRecurrenceSummary(marker)).not.toContain('FREQ');
    expect(recurrenceSummaryLine(reminder(marker))).toBe(
      "🔁 Repeats on a custom schedule this server can't edit"
    );
  });

  it('still gives supported rules and one-off reminders their usual lines', () => {
    expect(recurrenceSummaryLine(reminder({ frequency: 'daily', interval: 1 }))).toBe('🔁 Every day');
    expect(recurrenceSummaryLine(reminder(null))).toBeUndefined();
  });

  describe('isUnsupportedRecurrence', () => {
    it('is true only for the marker', () => {
      expect(isUnsupportedRecurrence(marker)).toBe(true);
      expect(isUnsupportedRecurrence({ frequency: 'weekly', interval: 1 })).toBe(false);
      expect(isUnsupportedRecurrence(null)).toBe(false);
      expect(isUnsupportedRecurrence(undefined)).toBe(false);
    });

    it('treats supported: true as a supported rule, not the marker', () => {
      expect(isUnsupportedRecurrence({ supported: true, frequency: 'daily', interval: 1 } as never)).toBe(false);
    });
  });
});
