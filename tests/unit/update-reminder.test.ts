import { describe, expect, it, vi } from 'vitest';
import {
  updateReminderHandler,
  updateReminderTool,
} from '../../src/tools/reminders/update-reminder.js';
import type { SwiftExecutor } from '../../src/executor/swift-executor.js';
import type { RecurrenceRule, Reminder, UnsupportedRecurrence } from '../../src/types/reminder.js';

const DUE = '2026-10-19T14:30:00.000Z';
const RULE: RecurrenceRule = {
  frequency: 'weekly',
  interval: 2,
  daysOfWeek: ['monday', 'wednesday'],
};
const NEEDS_DUE_DATE =
  'A recurring reminder needs a due date: pass dueDate as the first occurrence.';

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
    hasRecurrenceRules: false,
    recurrence: null,
    dueDateHasTime: false,
    ...overrides,
  };
}

function executorReturning(value: Reminder = reminder()) {
  const execute = vi.fn().mockResolvedValue(value);
  return { executor: { execute } as unknown as SwiftExecutor, execute };
}

/** The payload the CLI would receive, as JSON text (so undefined keys are really gone) */
async function payloadOf(args: Record<string, unknown>): Promise<string> {
  const { executor, execute } = executorReturning();
  await updateReminderHandler({ id: 'ID-1', title: 'Gym', ...args }, executor);
  expect(execute).toHaveBeenCalledTimes(1);
  expect(execute.mock.calls[0][0]).toBe('update-reminder');
  return JSON.stringify(execute.mock.calls[0][1]);
}

const textOf = (result: { content: Array<{ text: string }> }) => result.content[0].text;

describe('update_reminder tool definition', () => {
  const props = updateReminderTool.inputSchema.properties as Record<string, any>;

  it('advertises recurrence with the same field docs as create_reminder', async () => {
    const { createReminderTool } = await import('../../src/tools/reminders/create-reminder.js');
    const createProps = createReminderTool.inputSchema.properties as Record<string, any>;
    expect(props.recurrence.properties).toEqual(createProps.recurrence.properties);
    expect(props.recurrence.required).toEqual(['frequency']);
    expect(Object.keys(props.recurrence.properties)).toContain('nthWeekday');
  });

  it('allows null for dueDate and recurrence, and says what null does', () => {
    expect(props.dueDate.type).toEqual(['string', 'null']);
    expect(props.dueDate.description).toContain('null');
    expect(props.recurrence.type).toEqual(['object', 'null']);
    expect(props.recurrence.description).toContain('null');
  });

  it('keeps id and title as the only required fields', () => {
    expect(updateReminderTool.inputSchema.required).toEqual(['id', 'title']);
  });

  it('explains how to stop a reminder repeating', () => {
    const description = updateReminderTool.description ?? '';
    expect(description).toContain('recurrence: null');
    expect(description).toContain('complete_reminder');
    expect(description).toContain('get_reminder');
    expect(description).toMatch(/omitted.*unchanged/i);
    expect(description).toContain('pass null to clear');
  });
});

describe('update_reminder payload: dueDate', () => {
  it('omitted: the key is absent', async () => {
    const payload = await payloadOf({});
    expect(payload).not.toContain('dueDate');
  });

  it('null: the CLI receives "dueDate":null', async () => {
    const payload = await payloadOf({ dueDate: null });
    expect(JSON.parse(payload)).toHaveProperty('dueDate', null);
    expect(payload).toContain('"dueDate":null');
  });

  it('a string: the CLI receives it', async () => {
    expect(JSON.parse(await payloadOf({ dueDate: DUE }))).toHaveProperty('dueDate', DUE);
  });

  it('rejects a malformed date string', async () => {
    const { executor, execute } = executorReturning();
    await expect(
      updateReminderHandler({ id: 'ID-1', title: 'Gym', dueDate: 'next tuesday' }, executor)
    ).rejects.toThrow('dueDate must be a valid ISO 8601 date string');
    expect(execute).not.toHaveBeenCalled();
  });
});

describe('update_reminder payload: recurrence', () => {
  it('omitted: the key is absent', async () => {
    expect(await payloadOf({})).not.toContain('recurrence');
  });

  it('null: the CLI receives "recurrence":null', async () => {
    const payload = await payloadOf({ recurrence: null });
    expect(JSON.parse(payload)).toHaveProperty('recurrence', null);
    expect(payload).toContain('"recurrence":null');
  });

  it('an object: the CLI receives the rule', async () => {
    const payload = JSON.parse(await payloadOf({ recurrence: RULE, dueDate: DUE }));
    expect(payload.recurrence).toEqual(RULE);
    expect(payload.dueDate).toBe(DUE);
  });

  it('an object without interval gets the default of 1', async () => {
    const payload = JSON.parse(
      await payloadOf({ recurrence: { frequency: 'daily' }, dueDate: DUE })
    );
    expect(payload.recurrence).toEqual({ frequency: 'daily', interval: 1 });
  });

  it('an object with an invalid rule is rejected before the CLI is called', async () => {
    const { executor, execute } = executorReturning();
    await expect(
      updateReminderHandler(
        { id: 'ID-1', title: 'Gym', recurrence: { frequency: 'daily', daysOfWeek: ['monday'] } },
        executor
      )
    ).rejects.toThrow('daysOfWeek only applies to weekly rules');
    expect(execute).not.toHaveBeenCalled();
  });

  it('a rule without dueDate in the same call is left to the CLI (it knows the current due date)', async () => {
    const payload = JSON.parse(await payloadOf({ recurrence: RULE }));
    expect(payload.recurrence).toEqual(RULE);
    expect(payload).not.toHaveProperty('dueDate');
  });

  it('rejects the unsupported marker that get_reminder shows, with a useful message', async () => {
    const marker: UnsupportedRecurrence = { supported: false, rrule: 'FREQ=DAILY;BYDAY=MO' };
    const { executor, execute } = executorReturning();
    const attempt = updateReminderHandler(
      { id: 'ID-1', title: 'Gym', dueDate: DUE, recurrence: marker },
      executor
    );
    await expect(attempt).rejects.toThrow(/can't be sent back/);
    await expect(attempt).rejects.toThrow('recurrence: null');
    expect(execute).not.toHaveBeenCalled();
  });
});

describe('update_reminder payload: combinations', () => {
  it('a rename alone carries neither dueDate nor recurrence', async () => {
    const { executor, execute } = executorReturning();
    await updateReminderHandler({ id: 'ID-1', title: 'Renamed' }, executor);
    const payload = execute.mock.calls[0][1];
    expect(payload).toEqual({ id: 'ID-1', title: 'Renamed' });
    expect(Object.keys(payload)).toEqual(['id', 'title']);
  });

  it('dueDate null with recurrence null clears both', async () => {
    const payload = JSON.parse(await payloadOf({ dueDate: null, recurrence: null }));
    expect(payload).toMatchObject({ dueDate: null, recurrence: null });
  });

  it('dueDate null alone is forwarded (the CLI decides, it knows whether the reminder repeats)', async () => {
    const payload = JSON.parse(await payloadOf({ dueDate: null }));
    expect(payload).toHaveProperty('dueDate', null);
    expect(payload).not.toHaveProperty('recurrence');
  });

  it('recurrence null with a new dueDate is forwarded', async () => {
    const payload = JSON.parse(await payloadOf({ recurrence: null, dueDate: DUE }));
    expect(payload).toMatchObject({ recurrence: null, dueDate: DUE });
  });

  it('rejects a recurrence object together with dueDate null, before calling the CLI', async () => {
    const { executor, execute } = executorReturning();
    await expect(
      updateReminderHandler(
        { id: 'ID-1', title: 'Gym', dueDate: null, recurrence: RULE },
        executor
      )
    ).rejects.toThrow(NEEDS_DUE_DATE);
    expect(execute).not.toHaveBeenCalled();
  });

  it('still requires a title', async () => {
    const { executor } = executorReturning();
    await expect(updateReminderHandler({ id: 'ID-1' }, executor)).rejects.toThrow(/title/);
  });

  it('leaves url and notes as they were: omitted means not sent', async () => {
    const payload = JSON.parse(await payloadOf({ notes: 'n' }));
    expect(payload).toEqual({ id: 'ID-1', title: 'Gym', notes: 'n' });
  });
});

describe('update_reminder response', () => {
  it('shows the recurrence line for a recurring reminder', async () => {
    const { executor } = executorReturning(
      reminder({ dueDate: DUE, hasRecurrenceRules: true, recurrence: RULE })
    );
    const text = textOf(await updateReminderHandler({ id: 'ID-1', title: 'Gym' }, executor));
    expect(text).toContain('✅ Updated reminder: "Gym"');
    expect(text).toContain('🔁 Every 2 weeks on Mon, Wed');
    expect(text).toContain('ID: ID-1');
    expect(text).toContain('List: Personal');
  });

  it('shows the custom-schedule line for an unsupported rule, never the RRULE', async () => {
    const { executor } = executorReturning(
      reminder({
        dueDate: DUE,
        hasRecurrenceRules: true,
        recurrence: { supported: false, rrule: 'FREQ=MONTHLY;BYSETPOS=-1' },
      })
    );
    const text = textOf(await updateReminderHandler({ id: 'ID-1', title: 'Gym' }, executor));
    expect(text).toContain("🔁 Repeats on a custom schedule this server can't edit");
    expect(text).not.toContain('FREQ');
  });

  it('has no recurrence line for a one-off reminder, e.g. after recurrence: null', async () => {
    const { executor } = executorReturning(reminder({ dueDate: DUE }));
    const text = textOf(
      await updateReminderHandler({ id: 'ID-1', title: 'Gym', recurrence: null }, executor)
    );
    expect(text).not.toContain('🔁');
    expect(text).toBe('✅ Updated reminder: "Gym"\n\nID: ID-1\nList: Personal');
  });
});
