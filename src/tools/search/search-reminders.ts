import { SwiftExecutor } from '../../executor/swift-executor.js';
import { searchRemindersSchema, validateInput } from '../../validation/reminder-schemas.js';
import { formatReminderList } from '../format-reminders.js';
import type { Reminder } from '../../types/reminder.js';
import type { Tool } from '@modelcontextprotocol/sdk/types.js';

export const searchRemindersTool: Tool = {
  name: 'search_reminders',
  description: 'Search reminders by text in title or notes',
  inputSchema: {
    type: 'object',
    properties: {
      searchText: {
        type: 'string',
        description: 'Text to search for in title and notes (required)',
      },
      completed: {
        type: 'boolean',
        description: 'Filter by completion status (optional)',
      },
    },
    required: ['searchText'],
  },
};

export async function searchRemindersHandler(
  args: unknown,
  executor: SwiftExecutor
): Promise<{ content: Array<{ type: string; text: string }> }> {
  const validatedArgs = validateInput(searchRemindersSchema, args);
  const reminders = await executor.execute<Reminder[]>('search-reminders', validatedArgs);

  if (reminders.length === 0) {
    return {
      content: [
        {
          type: 'text',
          text: `No reminders found matching "${validatedArgs.searchText}"`,
        },
      ],
    };
  }

  const remindersList = formatReminderList(reminders, {
    firstLine: (r) => `${r.isCompleted ? '✅' : '⏳'} ${r.title}`,
    detailLines: (r) => [r.notes || 'No notes'],
    separator: '\n\n',
  });

  return {
    content: [
      {
        type: 'text',
        text: `Found ${reminders.length} reminder(s) matching "${validatedArgs.searchText}":\n\n${remindersList}`,
      },
    ],
  };
}

