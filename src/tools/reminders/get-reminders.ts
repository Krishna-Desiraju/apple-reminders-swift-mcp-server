import { SwiftExecutor } from '../../executor/swift-executor.js';
import { listRemindersSchema, validateInput } from '../../validation/reminder-schemas.js';
import { formatReminderList } from '../format-reminders.js';
import type { Reminder } from '../../types/reminder.js';
import type { Tool } from '@modelcontextprotocol/sdk/types.js';

/**
 * Tool definition for get_reminders (list all reminders)
 */
export const getRemindersListTool: Tool = {
  name: 'get_reminders',
  description: 'Get all reminders, optionally filtered by completion status',
  inputSchema: {
    type: 'object',
    properties: {
      completed: {
        type: 'boolean',
        description: 'Filter by completion status (true=completed, false=incomplete, omit=all)',
      },
    },
  },
};

/**
 * Handler for get_reminders tool
 */
export async function getRemindersListHandler(
  args: unknown,
  executor: SwiftExecutor
): Promise<{ content: Array<{ type: string; text: string }> }> {
  // Validate input
  const validatedArgs = validateInput(listRemindersSchema, args);

  // Execute Swift CLI
  const reminders = await executor.execute<Reminder[]>('list-reminders', validatedArgs);

  // Format response
  if (reminders.length === 0) {
    return {
      content: [
        {
          type: 'text',
          text: 'No reminders found.',
        },
      ],
    };
  }

  const remindersList = formatReminderList(reminders, {
    firstLine: (r) => {
      const status = r.isCompleted ? '✅' : '⏳';
      const dueDateStr = r.dueDate
        ? ` | Due: ${new Date(r.dueDate).toLocaleDateString()}`
        : '';
      return `${status} ${r.title}${dueDateStr}`;
    },
    detailLines: (r) => [`List: ${r.listName} | ID: ${r.id}`],
    separator: '\n\n',
  });

  const responseText = `Found ${reminders.length} reminder(s):\n\n${remindersList}`;

  return {
    content: [
      {
        type: 'text',
        text: responseText,
      },
    ],
  };
}

