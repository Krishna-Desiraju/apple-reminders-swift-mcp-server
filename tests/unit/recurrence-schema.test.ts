import { describe, expect, it } from 'vitest';
import { createReminderSchema, recurrenceRuleSchema } from '../../src/validation/reminder-schemas.js';

function messages(input: unknown): string[] {
  const result = recurrenceRuleSchema.safeParse(input);
  return result.success ? [] : result.error.issues.map((i) => i.message);
}

describe('recurrenceRuleSchema', () => {
  it('accepts daily and weekly rules and defaults interval to 1', () => {
    expect(recurrenceRuleSchema.parse({ frequency: 'daily' })).toEqual({
      frequency: 'daily',
      interval: 1,
    });
    expect(
      recurrenceRuleSchema.parse({
        frequency: 'weekly',
        interval: 2,
        daysOfWeek: ['monday', 'wednesday'],
      })
    ).toEqual({ frequency: 'weekly', interval: 2, daysOfWeek: ['monday', 'wednesday'] });
  });

  it('rejects an interval below 1 or that is not a whole number', () => {
    for (const interval of [0, -1, 1.5]) {
      expect(messages({ frequency: 'daily', interval })).toEqual([
        'interval must be a whole number, 1 or greater',
      ]);
    }
  });

  it('accepts only full lowercase weekday names', () => {
    for (const day of ['mon', 'Monday', 'someday', 2]) {
      const [message] = messages({ frequency: 'weekly', daysOfWeek: [day] });
      expect(message).toBe(
        'daysOfWeek must use full lowercase weekday names: sunday, monday, tuesday, wednesday, thursday, friday, saturday'
      );
    }
  });

  it('rejects daysOfWeek on anything but weekly', () => {
    expect(messages({ frequency: 'daily', daysOfWeek: ['monday'] })).toEqual([
      'daysOfWeek only applies to weekly rules',
    ]);
    expect(messages({ frequency: 'monthly', daysOfWeek: ['monday'] })).toEqual([
      'daysOfWeek only applies to weekly rules',
    ]);
  });

  it('rejects an empty daysOfWeek', () => {
    expect(messages({ frequency: 'weekly', daysOfWeek: [] })).toEqual([
      "daysOfWeek can't be empty: omit it to repeat on the due date's weekday",
    ]);
  });

  it('rejects unknown frequencies and unrecognized fields', () => {
    expect(messages({ frequency: 'hourly' })).toHaveLength(1);
    expect(messages({ frequency: 'daily', byDay: [1] })[0]).toMatch(/byDay/);
  });
});

const WEEKDAY_NAMES =
  'sunday, monday, tuesday, wednesday, thursday, friday, saturday';

describe('recurrenceRuleSchema full vocabulary', () => {
  it('accepts monthly days of the month', () => {
    expect(
      recurrenceRuleSchema.parse({ frequency: 'monthly', daysOfMonth: [1, 15, 31] })
    ).toEqual({ frequency: 'monthly', interval: 1, daysOfMonth: [1, 15, 31] });
  });

  it('accepts monthly and yearly nth weekdays, including the last', () => {
    expect(
      recurrenceRuleSchema.parse({
        frequency: 'monthly',
        nthWeekday: { ordinal: -1, weekday: 'friday' },
      }).nthWeekday
    ).toEqual({ ordinal: -1, weekday: 'friday' });
    expect(
      recurrenceRuleSchema.parse({
        frequency: 'yearly',
        monthsOfYear: [11],
        nthWeekday: { ordinal: 4, weekday: 'thursday' },
      })
    ).toEqual({
      frequency: 'yearly',
      interval: 1,
      monthsOfYear: [11],
      nthWeekday: { ordinal: 4, weekday: 'thursday' },
    });
  });

  it('accepts yearly months of the year', () => {
    expect(
      recurrenceRuleSchema.parse({ frequency: 'yearly', monthsOfYear: [3, 6] }).monthsOfYear
    ).toEqual([3, 6]);
  });

  it('accepts an inclusive end date, including a leap day', () => {
    for (const endDate of ['2026-12-31', '2028-02-29']) {
      expect(recurrenceRuleSchema.parse({ frequency: 'daily', endDate }).endDate).toBe(endDate);
    }
  });

  it('accepts an occurrence count', () => {
    expect(
      recurrenceRuleSchema.parse({ frequency: 'daily', occurrenceCount: 3 }).occurrenceCount
    ).toBe(3);
  });

  describe('fields that do not apply to the frequency', () => {
    it.each(['daily', 'weekly', 'yearly'])('rejects daysOfMonth on %s', (frequency) => {
      expect(messages({ frequency, daysOfMonth: [1] })).toEqual([
        'daysOfMonth only applies to monthly rules',
      ]);
    });

    it.each(['daily', 'weekly', 'monthly'])('rejects monthsOfYear on %s', (frequency) => {
      expect(messages({ frequency, monthsOfYear: [3] })).toEqual([
        'monthsOfYear only applies to yearly rules',
      ]);
    });

    it.each(['daily', 'weekly'])('rejects nthWeekday on %s', (frequency) => {
      expect(
        messages({ frequency, nthWeekday: { ordinal: 1, weekday: 'monday' } })
      ).toEqual(['nthWeekday only applies to monthly and yearly rules']);
    });
  });

  it('rejects daysOfMonth together with nthWeekday', () => {
    expect(
      messages({
        frequency: 'monthly',
        daysOfMonth: [1],
        nthWeekday: { ordinal: 1, weekday: 'monday' },
      })
    ).toEqual(['Use either daysOfMonth or nthWeekday, not both']);
  });

  it('rejects a yearly nthWeekday without monthsOfYear', () => {
    expect(
      messages({ frequency: 'yearly', nthWeekday: { ordinal: 4, weekday: 'thursday' } })
    ).toEqual([
      'A yearly nthWeekday needs monthsOfYear (e.g. the fourth Thursday of November)',
    ]);
  });

  it('rejects endDate together with occurrenceCount', () => {
    expect(
      messages({ frequency: 'daily', endDate: '2026-12-31', occurrenceCount: 3 })
    ).toEqual(['Use either endDate or occurrenceCount, not both']);
  });

  describe('ranges', () => {
    it.each([0, 32, -1, 1.5])('rejects daysOfMonth entry %s', (day) => {
      expect(messages({ frequency: 'monthly', daysOfMonth: [day] })).toEqual([
        'daysOfMonth must be whole numbers from 1 to 31',
      ]);
    });

    it('rejects an empty daysOfMonth', () => {
      expect(messages({ frequency: 'monthly', daysOfMonth: [] })).toEqual([
        "daysOfMonth can't be empty: omit it to repeat on the due date's day",
      ]);
    });

    it.each([0, 13, -1, 2.5])('rejects monthsOfYear entry %s', (month) => {
      expect(messages({ frequency: 'yearly', monthsOfYear: [month] })).toEqual([
        'monthsOfYear must be whole numbers from 1 to 12',
      ]);
    });

    it('rejects an empty monthsOfYear', () => {
      expect(messages({ frequency: 'yearly', monthsOfYear: [] })).toEqual([
        "monthsOfYear can't be empty: omit it to repeat in the due date's month",
      ]);
    });

    it.each([0, 6, -2, 1.5])('rejects nthWeekday ordinal %s', (ordinal) => {
      expect(
        messages({ frequency: 'monthly', nthWeekday: { ordinal, weekday: 'monday' } })
      ).toEqual(['nthWeekday.ordinal must be 1, 2, 3, 4, 5 or -1 (last)']);
    });

    it.each(['mon', 'Monday', 2])('rejects nthWeekday weekday %s', (weekday) => {
      expect(
        messages({ frequency: 'monthly', nthWeekday: { ordinal: 1, weekday } })
      ).toEqual([`nthWeekday.weekday must use a full lowercase weekday name: ${WEEKDAY_NAMES}`]);
    });

    it.each([0, -3, 1.5])('rejects occurrenceCount %s', (occurrenceCount) => {
      expect(messages({ frequency: 'daily', occurrenceCount })).toEqual([
        'occurrenceCount must be a whole number, 1 or greater',
      ]);
    });

    it.each([
      '2026-02-30',
      '2026-13-01',
      '2026-00-10',
      '2026-04-31',
      '2027-02-29',
      '2026-12-31T00:00:00Z',
      '12/31/2026',
      '2026-1-5',
      'tomorrow',
      '',
    ])('rejects malformed endDate %j', (endDate) => {
      expect(messages({ frequency: 'daily', endDate })).toEqual([
        'endDate must be a real calendar date in YYYY-MM-DD format (e.g. 2026-12-31)',
      ]);
    });

    it('rejects an endDate that is not a string', () => {
      expect(messages({ frequency: 'daily', endDate: 20261231 })).toEqual([
        'endDate must be a real calendar date in YYYY-MM-DD format (e.g. 2026-12-31)',
      ]);
    });

    it('rejects unrecognized fields inside nthWeekday', () => {
      expect(
        messages({
          frequency: 'monthly',
          nthWeekday: { ordinal: 1, weekday: 'monday', extra: true },
        })
      ).toHaveLength(1);
    });
  });
});

describe('createReminderSchema recurrence', () => {
  const rule = { frequency: 'weekly', interval: 2, daysOfWeek: ['monday'] };

  it('accepts a rule together with a due date', () => {
    const parsed = createReminderSchema.parse({
      title: 'Gym',
      dueDate: '2026-10-19T14:30:00Z',
      recurrence: rule,
    });
    expect(parsed.recurrence).toEqual(rule);
  });

  it('rejects a rule without a due date', () => {
    const result = createReminderSchema.safeParse({ title: 'Gym', recurrence: rule });
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues.map((i) => i.message)).toEqual([
        'A recurring reminder needs a due date: pass dueDate as the first occurrence.',
      ]);
      expect(result.error.issues[0].path).toEqual(['dueDate']);
    }
  });

  it('still accepts reminders without a rule or a due date', () => {
    expect(() => createReminderSchema.parse({ title: 'Milk' })).not.toThrow();
  });
});
