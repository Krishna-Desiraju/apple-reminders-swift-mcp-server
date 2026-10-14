import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import {
  completeReminderHandler,
  completeReminderTool,
  uncompleteReminderHandler,
  uncompleteReminderTool,
} from '../../src/tools/reminders/complete-reminder.js';
import type { SwiftExecutor } from '../../src/executor/swift-executor.js';
import type {
  CompleteOutcome,
  CompleteReminderResult,
  RecurrenceRule,
  Reminder,
  UncompleteReminderResult,
  UnsupportedRecurrence,
} from '../../src/types/reminder.js';

// The dates are real instants shown in the server's time zone, so pin it.
// October 2026 is daylight time in Chicago (UTC-5).
let originalTimeZone: string | undefined;
beforeAll(() => {
  originalTimeZone = process.env.TZ;
  process.env.TZ = 'America/Chicago';
});
afterAll(() => {
  if (originalTimeZone === undefined) delete process.env.TZ;
  else process.env.TZ = originalTimeZone;
});

// Midnight Chicago time: a date-only due date
const MON_OCT_12 = '2026-10-12T05:00:00Z';
const MON_OCT_19 = '2026-10-19T05:00:00Z';
// 1:00 AM and 2:00 AM Chicago time on Tue Oct 13
const TUE_OCT_13_1AM = '2026-10-13T06:00:00Z';
const TUE_OCT_13_2AM = '2026-10-13T07:00:00Z';
// 2:30 PM and 12:05 AM Chicago time: exercise the PM and minute parts
const MON_OCT_19_2_30PM = '2026-10-19T19:30:00Z';
const MON_OCT_12_12_05AM = '2026-10-12T05:05:00Z';

const WEEKLY: RecurrenceRule = { frequency: 'weekly', interval: 1, daysOfWeek: ['monday'] };
const UNSUPPORTED: UnsupportedRecurrence = {
  supported: false,
  rrule: 'FREQ=MONTHLY;INTERVAL=1;BYDAY=MO,TU;BYSETPOS=-1',
};

function reminder(overrides: Partial<Reminder> = {}): Reminder {
  return {
    id: 'ID-1',
    title: 'Gym',
    isCompleted: false,
    priority: 0,
    listId: 'list-1',
    listName: 'Personal',
    flagged: false,
    hasAlarms: false,
    hasRecurrenceRules: true,
    recurrence: WEEKLY,
    dueDateHasTime: false,
    ...overrides,
  };
}

function executorReturning(value: unknown) {
  const execute = vi.fn().mockResolvedValue(value);
  return { executor: { execute } as unknown as SwiftExecutor, execute };
}

async function complete(result: CompleteReminderResult): Promise<string> {
  const { executor, execute } = executorReturning(result);
  const response = await completeReminderHandler({ id: 'ID-1' }, executor);
  expect(execute).toHaveBeenCalledWith('complete-reminder', { id: 'ID-1' });
  return response.content[0].text;
}

async function uncomplete(result: UncompleteReminderResult): Promise<string> {
  const { executor, execute } = executorReturning(result);
  const response = await uncompleteReminderHandler({ id: 'ID-1' }, executor);
  expect(execute).toHaveBeenCalledWith('uncomplete-reminder', { id: 'ID-1' });
  return response.content[0].text;
}

const advanced = (
  overrides: Partial<Reminder>,
  previousDueDate: string | null
): CompleteReminderResult => ({
  reminder: reminder(overrides),
  outcome: 'advanced',
  previousDueDate,
});

describe('complete_reminder: advanced', () => {
  it('names the date it was due and the next occurrence', async () => {
    const text = await complete(advanced({ dueDate: MON_OCT_19 }, MON_OCT_12));
    expect(text).toBe('✅ Completed occurrence of "Gym" due Mon Oct 12. Next occurrence: Mon Oct 19.');
  });

  it('shows the time on both dates when the due date has one', async () => {
    const text = await complete(
      advanced({ dueDate: TUE_OCT_13_2AM, dueDateHasTime: true }, TUE_OCT_13_1AM)
    );
    expect(text).toBe(
      '✅ Completed occurrence of "Gym" due Tue Oct 13, 1:00 AM. Next occurrence: Tue Oct 13, 2:00 AM.'
    );
  });

  it('formats PM and non-zero minutes', async () => {
    const text = await complete(
      advanced({ dueDate: MON_OCT_19_2_30PM, dueDateHasTime: true }, MON_OCT_12_12_05AM)
    );
    expect(text).toBe(
      '✅ Completed occurrence of "Gym" due Mon Oct 12, 12:05 AM. Next occurrence: Mon Oct 19, 2:30 PM.'
    );
  });

  it('uses plain spaces, whatever the ICU version puts before AM/PM', async () => {
    const text = await complete(
      advanced({ dueDate: TUE_OCT_13_2AM, dueDateHasTime: true }, TUE_OCT_13_1AM)
    );
    expect(text).not.toMatch(/[  ]/);
  });

  it('adds the plural count after the next date for a count-based rule', async () => {
    const text = await complete(
      advanced({ dueDate: MON_OCT_19, recurrence: { ...WEEKLY, occurrenceCount: 3 } }, MON_OCT_12)
    );
    expect(text).toBe(
      '✅ Completed occurrence of "Gym" due Mon Oct 12. Next occurrence: Mon Oct 19 (3 occurrences left).'
    );
  });

  it('uses the singular for one occurrence left', async () => {
    const text = await complete(
      advanced({ dueDate: MON_OCT_19, recurrence: { ...WEEKLY, occurrenceCount: 1 } }, MON_OCT_12)
    );
    expect(text).toBe(
      '✅ Completed occurrence of "Gym" due Mon Oct 12. Next occurrence: Mon Oct 19 (1 occurrence left).'
    );
  });

  it('combines a count suffix with times', async () => {
    const text = await complete(
      advanced(
        {
          dueDate: TUE_OCT_13_2AM,
          dueDateHasTime: true,
          recurrence: { frequency: 'daily', interval: 1, occurrenceCount: 2 },
        },
        TUE_OCT_13_1AM
      )
    );
    expect(text).toBe(
      '✅ Completed occurrence of "Gym" due Tue Oct 13, 1:00 AM. Next occurrence: Tue Oct 13, 2:00 AM (2 occurrences left).'
    );
  });

  it('adds no count for an end-date rule', async () => {
    const text = await complete(
      advanced(
        { dueDate: MON_OCT_19, recurrence: { ...WEEKLY, endDate: '2026-12-31' } },
        MON_OCT_12
      )
    );
    expect(text).toBe('✅ Completed occurrence of "Gym" due Mon Oct 12. Next occurrence: Mon Oct 19.');
  });

  it('adds no count for an unsupported rule', async () => {
    const text = await complete(advanced({ dueDate: MON_OCT_19, recurrence: UNSUPPORTED }, MON_OCT_12));
    expect(text).toBe('✅ Completed occurrence of "Gym" due Mon Oct 12. Next occurrence: Mon Oct 19.');
  });

  it('never mentions the completed copy or the RRULE', async () => {
    const text = await complete(advanced({ dueDate: MON_OCT_19, recurrence: UNSUPPORTED }, MON_OCT_12));
    expect(text).not.toMatch(/copy|ID-|FREQ=/i);
  });
});

describe('complete_reminder: lastOccurrence and completed', () => {
  it('says it was the last occurrence', async () => {
    const text = await complete({
      reminder: reminder({ isCompleted: true, dueDate: MON_OCT_12 }),
      outcome: 'lastOccurrence',
      previousDueDate: MON_OCT_12,
    });
    expect(text).toBe('✅ Completed the last occurrence of "Gym". It won\'t repeat again.');
  });

  it('leaves the non-recurring text unchanged', async () => {
    const text = await complete({
      reminder: reminder({ isCompleted: true, hasRecurrenceRules: false, recurrence: null }),
      outcome: 'completed',
      previousDueDate: null,
    });
    expect(text).toBe('✅ Marked as complete: "Gym"');
  });

  it.each<CompleteOutcome>(['completed', 'advanced', 'lastOccurrence'])(
    'handles a missing due date for %s',
    async (outcome) => {
      const text = await complete({ reminder: reminder(), outcome, previousDueDate: null });
      expect(text).toContain('"Gym"');
      expect(text).not.toContain('undefined');
      expect(text).not.toContain('Invalid');
    }
  );
});

describe('uncomplete_reminder', () => {
  it('alreadyOpen: changes nothing and explains why', async () => {
    const text = await uncomplete({
      reminder: reminder({ dueDate: MON_OCT_19 }),
      outcome: 'alreadyOpen',
    });
    expect(text).toBe(
      '"Gym" is already open; it advanced to its next occurrence (Mon Oct 19) when completed. Completions of recurring reminders can\'t be undone. To move it back, update its due date.'
    );
  });

  it('alreadyOpen: shows the time when the due date has one', async () => {
    const text = await uncomplete({
      reminder: reminder({ dueDate: TUE_OCT_13_2AM, dueDateHasTime: true }),
      outcome: 'alreadyOpen',
    });
    expect(text).toContain('its next occurrence (Tue Oct 13, 2:00 AM) when completed.');
  });

  it('reopened: unchanged text', async () => {
    const text = await uncomplete({
      reminder: reminder({ hasRecurrenceRules: false, recurrence: null }),
      outcome: 'reopened',
    });
    expect(text).toBe('⏳ Marked as incomplete: "Gym"');
  });
});

describe('tool descriptions', () => {
  it('complete_reminder explains advancing and how to stop a reminder repeating', () => {
    const description = completeReminderTool.description ?? '';
    expect(description).toMatch(/advances it to its next occurrence/);
    expect(description).toContain('completed copy');
    expect(description).toContain('update_reminder');
    expect(description).toContain('recurrence: null');
  });

  it('uncomplete_reminder says completing a recurring reminder cannot be undone', () => {
    expect(uncompleteReminderTool.description ?? '').toContain('can\'t be undone');
  });
});
