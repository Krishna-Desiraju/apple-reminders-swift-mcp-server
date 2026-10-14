import { describe, expect, it, vi } from 'vitest';
import { getRemindersListHandler } from '../../src/tools/reminders/get-reminders.js';
import {
  getCompletedRemindersHandler,
  getOverdueRemindersHandler,
  getTodaysRemindersHandler,
} from '../../src/tools/search/date-based-reminders.js';
import { searchRemindersHandler } from '../../src/tools/search/search-reminders.js';
import type { SwiftExecutor } from '../../src/executor/swift-executor.js';
import type { Reminder } from '../../src/types/reminder.js';

// Pins the exact text of the five list-style tools. Date and time strings use the
// host locale, so expected values are computed with the same calls the tools make.
const date = (iso: string) => new Date(iso).toLocaleDateString();
const time = (iso: string) => new Date(iso).toLocaleTimeString();

function reminder(overrides: Partial<Reminder>): Reminder {
  return {
    id: 'ID-1',
    title: 'Untitled',
    isCompleted: false,
    priority: 0,
    listId: 'list-1',
    listName: 'Personal',
    flagged: false,
    hasAlarms: false,
    hasRecurrenceRules: false,
    recurrence: null,
    dueDateHasTime: true,
    ...overrides,
  };
}

function executorReturning(reminders: Reminder[]) {
  const execute = vi.fn().mockResolvedValue(reminders);
  return { executor: { execute } as unknown as SwiftExecutor, execute };
}

const DUE = '2026-10-19T14:30:00.000Z';
const DONE = '2026-10-12T09:15:00.000Z';

describe('get_reminders output', () => {
  it('says so when there are none', async () => {
    const { executor } = executorReturning([]);
    const result = await getRemindersListHandler({}, executor);
    expect(result.content).toEqual([{ type: 'text', text: 'No reminders found.' }]);
  });

  it('lists status, title, optional due date, list and ID', async () => {
    const { executor, execute } = executorReturning([
      reminder({ id: 'A', title: 'Gym', dueDate: DUE }),
      reminder({ id: 'B', title: 'Pay rent', isCompleted: true, listName: 'Home' }),
    ]);
    const result = await getRemindersListHandler({ completed: false }, executor);
    expect(execute).toHaveBeenCalledWith('list-reminders', { completed: false });
    expect(result.content).toEqual([
      {
        type: 'text',
        text:
          'Found 2 reminder(s):\n\n' +
          `1. ⏳ Gym | Due: ${date(DUE)}\n   List: Personal | ID: A\n\n` +
          '2. ✅ Pay rent\n   List: Home | ID: B',
      },
    ]);
  });
});

describe('get_todays_reminders output', () => {
  it('says so when there are none', async () => {
    const { executor } = executorReturning([]);
    const result = await getTodaysRemindersHandler({}, executor);
    expect(result.content).toEqual([{ type: 'text', text: '📅 No reminders due today!' }]);
  });

  it('lists title and due time, or All day without a due date', async () => {
    const { executor, execute } = executorReturning([
      reminder({ title: 'Standup', dueDate: DUE }),
      reminder({ title: 'Water plants' }),
    ]);
    const result = await getTodaysRemindersHandler({}, executor);
    expect(execute).toHaveBeenCalledWith('get-todays-reminders', {});
    expect(result.content).toEqual([
      {
        type: 'text',
        text:
          "📅 Today's reminders (2):\n\n" +
          `1. Standup (${time(DUE)})\n` +
          '2. Water plants (All day)',
      },
    ]);
  });
});

describe('get_overdue_reminders output', () => {
  it('says so when there are none', async () => {
    const { executor } = executorReturning([]);
    const result = await getOverdueRemindersHandler({}, executor);
    expect(result.content).toEqual([
      { type: 'text', text: "✨ No overdue reminders! You're all caught up!" },
    ]);
  });

  it('lists title and due date, or Unknown without one', async () => {
    const { executor, execute } = executorReturning([
      reminder({ title: 'File taxes', dueDate: DUE }),
      reminder({ title: 'Call mom' }),
    ]);
    const result = await getOverdueRemindersHandler({}, executor);
    expect(execute).toHaveBeenCalledWith('get-overdue-reminders', {});
    expect(result.content).toEqual([
      {
        type: 'text',
        text:
          '⚠️ Overdue reminders (2):\n\n' +
          `1. File taxes (Due: ${date(DUE)})\n` +
          '2. Call mom (Due: Unknown)',
      },
    ]);
  });
});

describe('get_completed_reminders output', () => {
  it('says so when there are none', async () => {
    const { executor } = executorReturning([]);
    const result = await getCompletedRemindersHandler({}, executor);
    expect(result.content).toEqual([
      { type: 'text', text: 'No completed reminders found in the specified range.' },
    ]);
  });

  it('lists title and completion date, or Unknown without one', async () => {
    const { executor, execute } = executorReturning([
      reminder({ title: 'Send invoice', isCompleted: true, completionDate: DONE }),
      reminder({ title: 'Book flights', isCompleted: true }),
    ]);
    const result = await getCompletedRemindersHandler(
      { startDate: '2026-10-01T00:00:00Z' },
      executor
    );
    expect(execute).toHaveBeenCalledWith('get-completed-reminders', {
      startDate: '2026-10-01T00:00:00Z',
    });
    expect(result.content).toEqual([
      {
        type: 'text',
        text:
          '✅ Completed reminders (2):\n\n' +
          `1. Send invoice (Completed: ${date(DONE)})\n` +
          '2. Book flights (Completed: Unknown)',
      },
    ]);
  });
});

describe('search_reminders output', () => {
  it('echoes the search text when nothing matches', async () => {
    const { executor } = executorReturning([]);
    const result = await searchRemindersHandler({ searchText: 'milk' }, executor);
    expect(result.content).toEqual([{ type: 'text', text: 'No reminders found matching "milk"' }]);
  });

  it('lists status, title and notes, or No notes', async () => {
    const { executor, execute } = executorReturning([
      reminder({ title: 'Buy milk', notes: 'Oat, 2L' }),
      reminder({ title: 'Milk the cow', isCompleted: true }),
    ]);
    const result = await searchRemindersHandler({ searchText: 'milk' }, executor);
    expect(execute).toHaveBeenCalledWith('search-reminders', { searchText: 'milk' });
    expect(result.content).toEqual([
      {
        type: 'text',
        text:
          'Found 2 reminder(s) matching "milk":\n\n' +
          '1. ⏳ Buy milk\n   Oat, 2L\n\n' +
          '2. ✅ Milk the cow\n   No notes',
      },
    ]);
  });
});
