import { SwiftExecutor } from '../../executor/swift-executor.js';
import { completeReminderSchema, validateInput } from '../../validation/reminder-schemas.js';
import { isUnsupportedRecurrence } from '../../types/reminder.js';
import type {
  CompleteReminderResult,
  Reminder,
  UncompleteReminderResult,
} from '../../types/reminder.js';
import type { Tool } from '@modelcontextprotocol/sdk/types.js';

/**
 * "Mon Oct 12", or "Tue Oct 13, 2:00 AM" when the due date has a time. English, no year, in the
 * server's local time zone (the zone the user sees). Built from parts so the output doesn't
 * depend on the punctuation or spaces a given ICU version puts in.
 */
function formatOccurrence(iso: string, hasTime: boolean): string {
  const date = new Date(iso);
  const part = (parts: Intl.DateTimeFormatPart[], type: Intl.DateTimeFormatPartTypes) =>
    parts.find((p) => p.type === type)?.value ?? '';

  // Built per call: a formatter picks up the process time zone when it is created
  const d = new Intl.DateTimeFormat('en-US', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
  }).formatToParts(date);
  const day = `${part(d, 'weekday')} ${part(d, 'month')} ${part(d, 'day')}`;
  if (!hasTime) return day;

  const t = new Intl.DateTimeFormat('en-US', {
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  }).formatToParts(date);
  return `${day}, ${part(t, 'hour')}:${part(t, 'minute')} ${part(t, 'dayPeriod')}`;
}

/** " (3 occurrences left)" for a count-based rule, otherwise nothing */
function occurrencesLeft(reminder: Reminder): string {
  const recurrence = reminder.recurrence;
  if (!recurrence || isUnsupportedRecurrence(recurrence)) return '';
  const count = recurrence.occurrenceCount;
  if (count === undefined) return '';
  return ` (${count} ${count === 1 ? 'occurrence' : 'occurrences'} left)`;
}

function completionText({ reminder, outcome, previousDueDate }: CompleteReminderResult): string {
  if (outcome === 'lastOccurrence') {
    return `✅ Completed the last occurrence of "${reminder.title}". It won't repeat again.`;
  }
  if (outcome === 'advanced') {
    const hasTime = reminder.dueDateHasTime;
    const was = previousDueDate ? ` due ${formatOccurrence(previousDueDate, hasTime)}` : '';
    let text = `✅ Completed occurrence of "${reminder.title}"${was}.`;
    if (reminder.dueDate) {
      text += ` Next occurrence: ${formatOccurrence(reminder.dueDate, hasTime)}`;
      text += `${occurrencesLeft(reminder)}.`;
    }
    return text;
  }
  return `✅ Marked as complete: "${reminder.title}"`;
}

function uncompletionText({ reminder, outcome }: UncompleteReminderResult): string {
  if (outcome === 'alreadyOpen') {
    const next = reminder.dueDate
      ? ` (${formatOccurrence(reminder.dueDate, reminder.dueDateHasTime)})`
      : '';
    return `"${reminder.title}" is already open; it advanced to its next occurrence${next} when completed. Completions of recurring reminders can't be undone. To move it back, update its due date.`;
  }
  return `⏳ Marked as incomplete: "${reminder.title}"`;
}

export const completeReminderTool: Tool = {
  name: 'complete_reminder',
  description:
    'Mark a reminder as complete. Completing a recurring reminder advances it to its next occurrence: it stays open and a completed copy is left behind. At its last occurrence it just completes. To stop a reminder repeating for good, call update_reminder with recurrence: null first, then complete it.',
  inputSchema: {
    type: 'object',
    properties: {
      id: {
        type: 'string',
        description: 'The reminder ID to mark as complete (required)',
      },
    },
    required: ['id'],
  },
};

export async function completeReminderHandler(
  args: unknown,
  executor: SwiftExecutor
): Promise<{ content: Array<{ type: string; text: string }> }> {
  const validatedArgs = validateInput(completeReminderSchema, args);
  const result = await executor.execute<CompleteReminderResult>('complete-reminder', validatedArgs);

  return {
    content: [
      {
        type: 'text',
        text: completionText(result),
      },
    ],
  };
}

export const uncompleteReminderTool: Tool = {
  name: 'uncomplete_reminder',
  description:
    'Mark a reminder as incomplete. A recurring reminder that is already open (it advanced when completed) is left unchanged, because completing a recurring reminder can\'t be undone; update its due date to move it back.',
  inputSchema: {
    type: 'object',
    properties: {
      id: {
        type: 'string',
        description: 'The reminder ID to mark as incomplete (required)',
      },
    },
    required: ['id'],
  },
};

export async function uncompleteReminderHandler(
  args: unknown,
  executor: SwiftExecutor
): Promise<{ content: Array<{ type: string; text: string }> }> {
  const validatedArgs = validateInput(completeReminderSchema, args);
  const result = await executor.execute<UncompleteReminderResult>(
    'uncomplete-reminder',
    validatedArgs
  );

  return {
    content: [
      {
        type: 'text',
        text: uncompletionText(result),
      },
    ],
  };
}

