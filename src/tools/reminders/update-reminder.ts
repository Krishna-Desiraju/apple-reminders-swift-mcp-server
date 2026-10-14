import { SwiftExecutor } from '../../executor/swift-executor.js';
import { updateReminderSchema, validateInput } from '../../validation/reminder-schemas.js';
import type { Reminder } from '../../types/reminder.js';
import { recurrenceSummaryLine } from '../recurrence-summary.js';
import { recurrenceInputSchema } from './create-reminder.js';
import type { Tool } from '@modelcontextprotocol/sdk/types.js';

export const updateReminderTool: Tool = {
  name: 'update_reminder',
  description:
    'Update an existing reminder with new attributes. dueDate and recurrence: omitted = unchanged, pass null to clear. ' +
    'To stop a reminder repeating, pass recurrence: null (the due date stays). ' +
    'To stop it repeating and finish it, pass recurrence: null, then call complete_reminder. ' +
    'To edit a recurrence rule, read it with get_reminder first and send the whole rule back, because it replaces the old one. ' +
    'A recurring reminder always needs a due date: clearing dueDate on one is rejected unless you also pass recurrence: null. ' +
    'Note: Reminders.app "Hourly" repeats show up here as daily ("Every day") because EventKit reports them that way; renaming, editing other fields and completing them is safe; setting recurrence on one replaces the hourly repeat.',
  inputSchema: {
    type: 'object',
    properties: {
      id: {
        type: 'string',
        description: 'The reminder ID to update (required)',
      },
      title: {
        type: 'string',
        description: 'New title for the reminder (required)',
      },
      notes: {
        type: 'string',
        description: 'New notes for the reminder',
      },
      listName: {
        type: 'string',
        description: 'Move to a different list',
      },
      dueDate: {
        type: ['string', 'null'],
        description:
          'New due date in ISO 8601 format. Omit to keep the current due date; pass null to clear it (a recurring reminder needs one, so also pass recurrence: null).',
      },
      priority: {
        type: 'number',
        description: 'Priority: 0=none, 1=high/urgent (!!!), 5=medium, 9=low',
        minimum: 0,
        maximum: 9,
      },
      tags: {
        type: 'array',
        items: { type: 'string' },
        description: 'New tags',
      },
      flagged: {
        type: 'boolean',
        description: 'Whether to flag this reminder',
      },
      url: {
        type: 'string',
        description: 'URL to associate',
      },
      recurrence: {
        ...recurrenceInputSchema,
        type: ['object', 'null'],
        description:
          'Set, replace or remove how this reminder repeats. Omit to leave it unchanged (including rules this server can\'t edit); pass null to stop it repeating; pass a rule to replace the current one. A rule needs a due date: the reminder must already have one or you pass dueDate as the first occurrence. Completing an occurrence moves the reminder to its next one.',
      },
    },
    required: ['id', 'title'],
  },
};

export async function updateReminderHandler(
  args: unknown,
  executor: SwiftExecutor
): Promise<{ content: Array<{ type: string; text: string }> }> {
  const validatedArgs = validateInput(updateReminderSchema, args);
  const reminder = await executor.execute<Reminder>('update-reminder', validatedArgs);

  const recurrenceLine = recurrenceSummaryLine(reminder);
  const text =
    `✅ Updated reminder: "${reminder.title}"\n\nID: ${reminder.id}\nList: ${reminder.listName}` +
    (recurrenceLine ? `\n${recurrenceLine}` : '');

  return { content: [{ type: 'text', text }] };
}

