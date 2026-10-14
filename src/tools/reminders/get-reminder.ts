import { SwiftExecutor } from '../../executor/swift-executor.js';
import { getReminderSchema, validateInput } from '../../validation/reminder-schemas.js';
import { recurrenceSummaryLine } from '../recurrence-summary.js';
import { formatPriority } from './create-reminder.js';
import type { Reminder } from '../../types/reminder.js';
import type { Tool } from '@modelcontextprotocol/sdk/types.js';

/**
 * Tool definition for get_reminder
 */
export const getReminderTool: Tool = {
  name: 'get_reminder',
  description:
    'Get one reminder by ID with full detail: title, list, notes, URL, priority, due date and, for a recurring reminder, its recurrence rule as JSON. ' +
    'Note: Reminders.app "Hourly" repeats show up here as daily ("Every day") because EventKit reports them that way; renaming, editing other fields and completing them is safe; setting recurrence on one replaces the hourly repeat.',
  inputSchema: {
    type: 'object',
    properties: {
      id: {
        type: 'string',
        description: 'The reminder ID (required)',
      },
    },
    required: ['id'],
  },
};

/**
 * Handler for get_reminder tool
 */
export async function getReminderHandler(
  args: unknown,
  executor: SwiftExecutor
): Promise<{ content: Array<{ type: string; text: string }> }> {
  const validatedArgs = validateInput(getReminderSchema, args);
  const reminder = await executor.execute<Reminder>('get-reminder', validatedArgs);

  const lines = [
    `${reminder.isCompleted ? '✅' : '⏳'} ${reminder.title}`,
    '',
    `ID: ${reminder.id}`,
    `List: ${reminder.listName}`,
    `Status: ${reminder.isCompleted ? 'Completed' : 'Open'}`,
    reminder.dueDate ? `Due: ${formatDueDate(reminder)}` : 'No due date',
  ];

  const summaryLine = recurrenceSummaryLine(reminder);
  if (summaryLine) lines.push(summaryLine);
  if (reminder.priority > 0) lines.push(`Priority: ${formatPriority(reminder.priority)}`);
  if (reminder.url) lines.push(`URL: ${reminder.url}`);
  if (reminder.notes) lines.push('', 'Notes:', reminder.notes);
  if (reminder.recurrence) {
    lines.push('', 'Recurrence rule:', JSON.stringify(reminder.recurrence, null, 2));
  }

  return {
    content: [
      {
        type: 'text',
        text: lines.join('\n'),
      },
    ],
  };
}

/**
 * Show the time only when the due date has one
 */
function formatDueDate(reminder: Reminder): string {
  const date = new Date(reminder.dueDate as string);
  return reminder.dueDateHasTime ? date.toLocaleString() : date.toLocaleDateString();
}
