import { SwiftExecutor } from '../../executor/swift-executor.js';
import { completedRemindersSchema, validateInput } from '../../validation/reminder-schemas.js';
import { formatReminderList } from '../format-reminders.js';
import type { Reminder } from '../../types/reminder.js';
import type { Tool } from '@modelcontextprotocol/sdk/types.js';

export const getTodaysRemindersTool: Tool = {
  name: 'get_todays_reminders',
  description: 'Get all reminders due today',
  inputSchema: {
    type: 'object',
    properties: {},
  },
};

export async function getTodaysRemindersHandler(
  _args: unknown,
  executor: SwiftExecutor
): Promise<{ content: Array<{ type: string; text: string }> }> {
  const reminders = await executor.execute<Reminder[]>('get-todays-reminders', {});

  if (reminders.length === 0) {
    return {
      content: [
        {
          type: 'text',
          text: '📅 No reminders due today!',
        },
      ],
    };
  }

  const remindersList = formatReminderList(reminders, {
    firstLine: (r) => {
      const time = r.dueDate ? new Date(r.dueDate).toLocaleTimeString() : 'All day';
      return `${r.title} (${time})`;
    },
    separator: '\n',
  });

  return {
    content: [
      {
        type: 'text',
        text: `📅 Today's reminders (${reminders.length}):\n\n${remindersList}`,
      },
    ],
  };
}

export const getOverdueRemindersTool: Tool = {
  name: 'get_overdue_reminders',
  description: 'Get all overdue reminders',
  inputSchema: {
    type: 'object',
    properties: {},
  },
};

export async function getOverdueRemindersHandler(
  _args: unknown,
  executor: SwiftExecutor
): Promise<{ content: Array<{ type: string; text: string }> }> {
  const reminders = await executor.execute<Reminder[]>('get-overdue-reminders', {});

  if (reminders.length === 0) {
    return {
      content: [
        {
          type: 'text',
          text: '✨ No overdue reminders! You\'re all caught up!',
        },
      ],
    };
  }

  const remindersList = formatReminderList(reminders, {
    firstLine: (r) => {
      const dueDate = r.dueDate ? new Date(r.dueDate).toLocaleDateString() : 'Unknown';
      return `${r.title} (Due: ${dueDate})`;
    },
    separator: '\n',
  });

  return {
    content: [
      {
        type: 'text',
        text: `⚠️ Overdue reminders (${reminders.length}):\n\n${remindersList}`,
      },
    ],
  };
}

export const getCompletedRemindersTool: Tool = {
  name: 'get_completed_reminders',
  description: 'Get completed reminders within a date range',
  inputSchema: {
    type: 'object',
    properties: {
      startDate: {
        type: 'string',
        description: 'Start date in ISO 8601 format (optional)',
      },
      endDate: {
        type: 'string',
        description: 'End date in ISO 8601 format (optional)',
      },
    },
  },
};

export async function getCompletedRemindersHandler(
  args: unknown,
  executor: SwiftExecutor
): Promise<{ content: Array<{ type: string; text: string }> }> {
  const validatedArgs = validateInput(completedRemindersSchema, args);
  const reminders = await executor.execute<Reminder[]>('get-completed-reminders', validatedArgs);

  if (reminders.length === 0) {
    return {
      content: [
        {
          type: 'text',
          text: 'No completed reminders found in the specified range.',
        },
      ],
    };
  }

  const remindersList = formatReminderList(reminders, {
    firstLine: (r) => {
      const completedDate = r.completionDate
        ? new Date(r.completionDate).toLocaleDateString()
        : 'Unknown';
      return `${r.title} (Completed: ${completedDate})`;
    },
    separator: '\n',
  });

  return {
    content: [
      {
        type: 'text',
        text: `✅ Completed reminders (${reminders.length}):\n\n${remindersList}`,
      },
    ],
  };
}

