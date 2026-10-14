/**
 * Opt-in live suite for recurring reminders. It drives the REAL Swift CLI against the user's
 * real Reminders data, so it is skipped unless RUN_LIVE_REMINDERS=1:
 *
 *   npm run build:swift   # once, builds swift-cli/RemindersCLI.app
 *   npm run test:live
 *
 * Safety: everything happens in a list this suite creates itself, named
 * `mcp-live-test-<timestamp>-<random>`. It aborts before creating anything if a list with that
 * name already exists, and afterAll deletes ONLY the list ID it created (after re-checking that
 * the ID still carries that name). Other lists and reminders are never modified; the only reads
 * outside the throwaway list are get-all-lists and a title search for this run's unique titles.
 */
import { existsSync } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { SwiftExecutor } from '../../src/executor/swift-executor.js';
import { createListHandler } from '../../src/tools/lists/create-list.js';
import {
  completeReminderHandler,
  uncompleteReminderHandler,
} from '../../src/tools/reminders/complete-reminder.js';
import { createReminderHandler } from '../../src/tools/reminders/create-reminder.js';
import { getReminderHandler } from '../../src/tools/reminders/get-reminder.js';
import { updateReminderHandler } from '../../src/tools/reminders/update-reminder.js';
import { searchRemindersHandler } from '../../src/tools/search/search-reminders.js';
import type { DeleteListResult, ReminderList } from '../../src/types/list.js';
import type {
  CompleteReminderResult,
  RecurrenceRule,
  Reminder,
  UncompleteReminderResult,
  Weekday,
} from '../../src/types/reminder.js';

const ENABLED = process.env.RUN_LIVE_REMINDERS === '1';

/** Each CLI call can take a second or two through `open`. */
const TIMEOUT = 60_000;

const WEEKDAY_NAMES: Weekday[] = [
  'sunday',
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
];
const WEEKDAY_ABBREVIATIONS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/** Local-time 09:00, `daysFromToday` days from now */
function localNineAm(daysFromToday: number): Date {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), now.getDate() + daysFromToday, 9, 0, 0, 0);
}

/** Local-time 09:00 on the first Monday of next month */
function firstMondayOfNextMonth(): Date {
  const now = new Date();
  const date = new Date(now.getFullYear(), now.getMonth() + 1, 1, 9, 0, 0, 0);
  while (date.getDay() !== 1) date.setDate(date.getDate() + 1);
  return date;
}

/** Remembers the last response of every CLI command, so tests can assert on `outcome` */
class RecordingExecutor extends SwiftExecutor {
  readonly last = new Map<string, unknown>();

  override async execute<T>(command: string, args: unknown = {}): Promise<T> {
    const result = await super.execute<T>(command, args);
    this.last.set(command, result);
    return result;
  }

  lastResult<T>(command: string): T {
    if (!this.last.has(command)) throw new Error(`No ${command} response recorded`);
    return this.last.get(command) as T;
  }
}

const textOf = (result: { content: Array<{ text: string }> }) => result.content[0].text;

describe.runIf(ENABLED)('recurring reminders (live, real Reminders)', () => {
  const stamp = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
  const listName = `mcp-live-test-${stamp}`;
  let executor: RecordingExecutor;
  let preexistingListIds = new Set<string>();
  let listId: string | undefined;
  let creationAttempted = false;

  /** Titles embed the run stamp, so a title search can only ever match this run's reminders. */
  const title = (label: string) => `${listName} ${label}`;

  async function getReminder(id: string): Promise<Reminder> {
    return executor.execute<Reminder>('get-reminder', { id });
  }

  /** Create through the tool handler (the path the server uses) and return the stored reminder. */
  async function createViaHandler(args: Record<string, unknown>): Promise<Reminder> {
    const text = textOf(await createReminderHandler({ listName, ...args }, executor));
    const id = /^ID: (.+)$/m.exec(text)?.[1];
    if (!id) throw new Error(`create_reminder response had no ID:\n${text}`);
    return getReminder(id);
  }

  async function lists(): Promise<ReminderList[]> {
    return executor.execute<ReminderList[]>('get-all-lists', {});
  }

  beforeAll(async () => {
    executor = new RecordingExecutor();

    const swiftCliDir = path.resolve(
      path.dirname(fileURLToPath(import.meta.url)),
      '../../swift-cli'
    );
    const hasBinary =
      existsSync(path.join(swiftCliDir, 'RemindersCLI.app/Contents/MacOS/reminders-cli')) ||
      existsSync(path.join(swiftCliDir, '.build/release/reminders-cli'));
    if (!hasBinary) {
      throw new Error('Swift CLI not built. Run `npm run build:swift` first.');
    }

    // Safety guard: never reuse a list that already exists under this name
    const before = await lists();
    preexistingListIds = new Set(before.map((l) => l.id));
    const clash = before.find((l) => l.title.toLowerCase() === listName.toLowerCase());
    if (clash) {
      throw new Error(`Refusing to run: a list named "${listName}" already exists (${clash.id})`);
    }

    creationAttempted = true;
    const created = textOf(await createListHandler({ name: listName }, executor));
    const createdList = executor.lastResult<ReminderList>('create-list');
    listId = createdList.id;
    expect(createdList.title).toBe(listName);
    expect(preexistingListIds.has(createdList.id)).toBe(false);
    expect(created).toContain(listName);
  }, TIMEOUT);

  afterAll(async () => {
    // Runs even when tests or beforeAll failed. Deletes only the ID this run created.
    if (!executor || !creationAttempted) return; // nothing was created, nothing to clean up

    let idToDelete = listId;
    if (!idToDelete) {
      // create-list may have failed after the list was made; it can only be our brand-new list
      const orphan = (await lists()).find(
        (l) => l.title === listName && !preexistingListIds.has(l.id)
      );
      idToDelete = orphan?.id;
    }
    if (!idToDelete) return;

    const ours = (await lists()).find((l) => l.id === idToDelete);
    if (!ours) return; // already gone
    if (ours.title !== listName) {
      throw new Error(
        `Refusing to delete list ${idToDelete}: expected title "${listName}", found "${ours.title}"`
      );
    }

    const result = await executor.execute<DeleteListResult>('delete-list', { id: idToDelete });
    expect(result.id).toBe(idToDelete);

    const remaining = (await lists()).find((l) => l.id === idToDelete);
    if (remaining) {
      throw new Error(`Throwaway list "${listName}" (${idToDelete}) was NOT deleted; remove it by hand`);
    }
  }, TIMEOUT);

  // Steps 1 to 3 share one reminder
  let weekly: Reminder;
  let weeklyDue: Date;
  let weeklyDay: Weekday;

  it(
    '1. creates a weekly recurring reminder, reads it back and shows the repeat line in lists',
    async () => {
      weeklyDue = localNineAm(1);
      weeklyDay = WEEKDAY_NAMES[weeklyDue.getDay()];

      weekly = await createViaHandler({
        title: title('weekly'),
        dueDate: weeklyDue.toISOString(),
        recurrence: { frequency: 'weekly', daysOfWeek: [weeklyDay] },
      });

      const got = await getReminder(weekly.id);
      expect(got.listName).toBe(listName);
      expect(got.recurrence).toMatchObject({
        frequency: 'weekly',
        interval: 1,
        daysOfWeek: [weeklyDay],
      });
      expect(new Date(got.dueDate as string).getTime()).toBe(weeklyDue.getTime());
      expect(got.dueDateHasTime).toBe(true);

      const summary = `🔁 Every week on ${WEEKDAY_ABBREVIATIONS[weeklyDue.getDay()]}`;
      const getText = textOf(await getReminderHandler({ id: weekly.id }, executor));
      expect(getText).toContain(summary);
      expect(getText).toContain('Recurrence rule:');

      const searchText = textOf(
        await searchRemindersHandler({ searchText: title('weekly') }, executor)
      );
      expect(searchText).toContain(summary);
    },
    TIMEOUT
  );

  it(
    '2. renaming alone leaves recurrence and due date unchanged',
    async () => {
      expect(weekly, 'step 1 must have created the reminder').toBeDefined();
      const before = await getReminder(weekly.id);

      const text = textOf(
        await updateReminderHandler({ id: weekly.id, title: title('weekly renamed') }, executor)
      );
      expect(text).toContain('🔁 Every week');

      const after = await getReminder(weekly.id);
      expect(after.title).toBe(title('weekly renamed'));
      expect(after.recurrence).toEqual(before.recurrence);
      expect(after.dueDate).toBe(before.dueDate);
    },
    TIMEOUT
  );

  it(
    '3. recurrence: null with dueDate: null clears both, then a new rule can be set',
    async () => {
      expect(weekly, 'step 1 must have created the reminder').toBeDefined();

      await updateReminderHandler(
        { id: weekly.id, title: title('weekly renamed'), recurrence: null, dueDate: null },
        executor
      );
      const cleared = await getReminder(weekly.id);
      expect(cleared.recurrence).toBeNull();
      expect(cleared.dueDate).toBeFalsy();

      const newDue = localNineAm(3);
      const text = textOf(
        await updateReminderHandler(
          {
            id: weekly.id,
            title: title('weekly renamed'),
            dueDate: newDue.toISOString(),
            recurrence: { frequency: 'daily', interval: 2 },
          },
          executor
        )
      );
      expect(text).toContain('🔁 Every 2 days');

      const after = await getReminder(weekly.id);
      expect(after.recurrence).toMatchObject({ frequency: 'daily', interval: 2 });
      expect(new Date(after.dueDate as string).getTime()).toBe(newDue.getTime());
    },
    TIMEOUT
  );

  it(
    '4. rejects a rule without a due date, and clearing the due date under a rule',
    async () => {
      // Rejected by the TypeScript schema
      await expect(
        createReminderHandler(
          {
            listName,
            title: title('no due date'),
            recurrence: { frequency: 'daily' },
          },
          executor
        )
      ).rejects.toThrow(/needs a due date/);

      // Rejected by the Swift CLI itself when the schema is bypassed
      await expect(
        executor.execute<Reminder>('create-reminder', {
          listName,
          title: title('no due date (cli)'),
          recurrence: { frequency: 'daily' },
        })
      ).rejects.toThrow(/needs a due date/);

      // Neither attempt may have left a reminder behind
      const found = textOf(await searchRemindersHandler({ searchText: 'no due date' }, executor));
      expect(found).not.toContain(listName);

      // Clearing dueDate while the rule stays is rejected by the CLI and changes nothing
      const recurring = await createViaHandler({
        title: title('keeps its date'),
        dueDate: localNineAm(2).toISOString(),
        recurrence: { frequency: 'weekly' },
      });
      await expect(
        updateReminderHandler({ id: recurring.id, title: recurring.title, dueDate: null }, executor)
      ).rejects.toThrow(/repeats, so it needs a due date/);

      const after = await getReminder(recurring.id);
      expect(after.dueDate).toBe(recurring.dueDate);
      expect(after.recurrence).toEqual(recurring.recurrence);
    },
    TIMEOUT
  );

  it(
    '5. a daily rule with occurrenceCount 2 advances once, then completes on its last occurrence',
    async () => {
      const due = localNineAm(0);
      const created = await createViaHandler({
        title: title('count two'),
        dueDate: due.toISOString(),
        recurrence: { frequency: 'daily', occurrenceCount: 2 },
      });
      expect((created.recurrence as RecurrenceRule).occurrenceCount).toBe(2);

      // First completion: advances to the next occurrence
      const firstText = textOf(await completeReminderHandler({ id: created.id }, executor));
      const first = executor.lastResult<CompleteReminderResult>('complete-reminder');
      expect(first.outcome).toBe('advanced');
      expect(first.reminder.id).toBe(created.id);
      expect(first.reminder.isCompleted).toBe(false);
      expect(new Date(first.previousDueDate as string).getTime()).toBe(due.getTime());
      expect(firstText).toContain('Next occurrence');

      const advanced = await getReminder(created.id);
      expect(advanced.isCompleted).toBe(false);
      expect(new Date(advanced.dueDate as string).getTime()).toBeGreaterThan(due.getTime());
      expect(new Date(advanced.dueDate as string).getTime()).toBe(localNineAm(1).getTime());
      expect((advanced.recurrence as RecurrenceRule).occurrenceCount).toBe(1);

      // Second completion: no next occurrence, so it completes for good
      const secondText = textOf(await completeReminderHandler({ id: created.id }, executor));
      const second = executor.lastResult<CompleteReminderResult>('complete-reminder');
      expect(second.outcome).toBe('lastOccurrence');
      expect(second.reminder.id).toBe(created.id);
      expect(secondText).toContain('last occurrence');

      const done = await getReminder(created.id);
      expect(done.isCompleted).toBe(true);
    },
    TIMEOUT
  );

  it(
    '6. uncompleting an advanced recurring reminder is a no-op reported as already open',
    async () => {
      const due = localNineAm(0);
      const created = await createViaHandler({
        title: title('uncomplete'),
        dueDate: due.toISOString(),
        recurrence: { frequency: 'daily' },
      });

      await completeReminderHandler({ id: created.id }, executor);
      expect(executor.lastResult<CompleteReminderResult>('complete-reminder').outcome).toBe(
        'advanced'
      );
      const advanced = await getReminder(created.id);
      expect(advanced.isCompleted).toBe(false);

      const text = textOf(await uncompleteReminderHandler({ id: created.id }, executor));
      const result = executor.lastResult<UncompleteReminderResult>('uncomplete-reminder');
      expect(result.outcome).toBe('alreadyOpen');
      expect(text).toContain('already open');

      const after = await getReminder(created.id);
      expect(after.isCompleted).toBe(false);
      expect(after.dueDate).toBe(advanced.dueDate);
      expect(after.recurrence).toEqual(advanced.recurrence);
    },
    TIMEOUT
  );

  it(
    '7. a monthly "first Monday" rule round-trips as nthWeekday',
    async () => {
      const due = firstMondayOfNextMonth();
      const created = await createViaHandler({
        title: title('first monday'),
        dueDate: due.toISOString(),
        recurrence: { frequency: 'monthly', nthWeekday: { ordinal: 1, weekday: 'monday' } },
      });

      const got = await getReminder(created.id);
      expect(got.recurrence).toMatchObject({
        frequency: 'monthly',
        interval: 1,
        nthWeekday: { ordinal: 1, weekday: 'monday' },
      });
      expect((got.recurrence as RecurrenceRule).daysOfMonth).toBeUndefined();
      expect(new Date(got.dueDate as string).getTime()).toBe(due.getTime());

      const text = textOf(await getReminderHandler({ id: created.id }, executor));
      expect(text).toContain('🔁 Every month on the first Monday');
    },
    TIMEOUT
  );
});
