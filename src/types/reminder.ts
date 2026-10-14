export type Weekday =
  | 'sunday'
  | 'monday'
  | 'tuesday'
  | 'wednesday'
  | 'thursday'
  | 'friday'
  | 'saturday';

export type RecurrenceFrequency = 'daily' | 'weekly' | 'monthly' | 'yearly';

/** "The first Monday" is `{ ordinal: 1, weekday: 'monday' }`; ordinal -1 means the last one. */
export interface NthWeekday {
  ordinal: 1 | 2 | 3 | 4 | 5 | -1;
  weekday: Weekday;
}

/**
 * Recurrence rule, used for input (create) and output (get_reminder, list tools)
 */
export interface RecurrenceRule {
  frequency: RecurrenceFrequency;
  interval: number; // integer >= 1
  daysOfWeek?: Weekday[]; // weekly only
  daysOfMonth?: number[]; // monthly only, 1-31
  nthWeekday?: NthWeekday; // monthly or yearly
  monthsOfYear?: number[]; // yearly only, 1-12
  endDate?: string; // YYYY-MM-DD, inclusive
  occurrenceCount?: number; // occurrences remaining, including the current one
}

/**
 * What a read reports for a rule this server can't express exactly (several rules, week-of-year
 * rules, "last weekday" patterns, ...). Only this shape carries a `supported` key; supported
 * rules omit it. `rrule` is EventKit's RRULE text, one rule per line when there are several.
 */
export interface UnsupportedRecurrence {
  supported: false;
  rrule: string;
}

/** A reminder's recurrence on read: a rule this server understands, or the unsupported marker. */
export type ReminderRecurrence = RecurrenceRule | UnsupportedRecurrence;

export function isUnsupportedRecurrence(
  recurrence: ReminderRecurrence | null | undefined
): recurrence is UnsupportedRecurrence {
  return (
    recurrence !== null &&
    recurrence !== undefined &&
    'supported' in recurrence &&
    recurrence.supported === false
  );
}

/**
 * Reminder data model
 */
export interface Reminder {
  id: string;
  title: string;
  notes?: string;
  isCompleted: boolean;
  priority: number;
  dueDate?: string; // ISO 8601 format
  completionDate?: string;
  creationDate?: string;
  modificationDate?: string;
  listId: string;
  listName: string;
  flagged: boolean;
  url?: string;
  hasAlarms: boolean;
  hasRecurrenceRules: boolean;
  recurrence: ReminderRecurrence | null; // null for a reminder that doesn't repeat
  dueDateHasTime: boolean; // false for a date-only due date
}

/**
 * What completing a reminder did, as reported by the `complete-reminder` command.
 * `advanced`: a recurring reminder moved to its next occurrence and is still open.
 * `lastOccurrence`: a recurring reminder had no next occurrence and is completed for good.
 * `completed`: a reminder that doesn't repeat is now completed.
 */
export type CompleteOutcome = 'completed' | 'advanced' | 'lastOccurrence';

/** Data of the `complete-reminder` response. */
export interface CompleteReminderResult {
  reminder: Reminder; // after the save; for `advanced`, the same reminder at its next occurrence
  outcome: CompleteOutcome;
  previousDueDate: string | null; // ISO 8601 due date before the save; whether it had a time is reminder.dueDateHasTime
}

/**
 * What uncompleting a reminder did.
 * `reopened`: the reminder is open again.
 * `alreadyOpen`: a recurring reminder that was already open; nothing was changed.
 */
export type UncompleteOutcome = 'reopened' | 'alreadyOpen';

/** Data of the `uncomplete-reminder` response. */
export interface UncompleteReminderResult {
  reminder: Reminder;
  outcome: UncompleteOutcome;
}

/**
 * Input for creating a reminder
 */
export interface CreateReminderInput {
  title: string;
  notes?: string;
  listName?: string;
  dueDate?: string; // ISO 8601 format
  priority?: number; // 0-9 scale
  flagged?: boolean;
  url?: string;
  tags?: string[];
  recurrence?: RecurrenceRule;
}

/**
 * Input for updating a reminder
 */
export interface UpdateReminderInput {
  id: string;
  title?: string;
  notes?: string;
  listName?: string;
  dueDate?: string | null; // omitted = unchanged, null = cleared
  priority?: number;
  flagged?: boolean;
  url?: string;
  tags?: string[];
  recurrence?: RecurrenceRule | null; // omitted = unchanged, null = rule removed
}

