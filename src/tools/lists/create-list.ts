import { SwiftExecutor } from '../../executor/swift-executor.js';
import { createListSchema } from '../../validation/list-schemas.js';
import { validateInput } from '../../validation/reminder-schemas.js';
import type { ReminderList } from '../../types/list.js';
import type { Tool } from '@modelcontextprotocol/sdk/types.js';

/**
 * Tool definition for create_list
 */
export const createListTool: Tool = {
  name: 'create_list',
  description: 'Create a new reminder list',
  inputSchema: {
    type: 'object',
    properties: {
      name: {
        type: 'string',
        description: 'Name of the new list (required)',
      },
      color: {
        type: 'string',
        description: 'List color as hex, e.g. "#FF9500"',
      },
      source: {
        type: 'string',
        description:
          'Account to create the list in, e.g. "iCloud" (defaults to the account of the default list)',
      },
    },
    required: ['name'],
  },
};

/**
 * Handler for create_list tool
 */
export async function createListHandler(
  args: unknown,
  executor: SwiftExecutor
): Promise<{ content: Array<{ type: string; text: string }> }> {
  const validatedArgs = validateInput(createListSchema, args);
  const list = await executor.execute<ReminderList>('create-list', validatedArgs);

  return {
    content: [
      {
        type: 'text',
        text: `✅ Created list: "${list.title}"\n\nID: ${list.id}\nAccount: ${list.source ?? 'unknown'}${list.color ? `\nColor: ${list.color}` : ''}`,
      },
    ],
  };
}
