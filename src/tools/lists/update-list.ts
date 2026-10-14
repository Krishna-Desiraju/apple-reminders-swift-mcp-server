import { SwiftExecutor } from '../../executor/swift-executor.js';
import { updateListSchema } from '../../validation/list-schemas.js';
import { validateInput } from '../../validation/reminder-schemas.js';
import type { ReminderList } from '../../types/list.js';
import type { Tool } from '@modelcontextprotocol/sdk/types.js';

/**
 * Tool definition for update_list
 */
export const updateListTool: Tool = {
  name: 'update_list',
  description: 'Rename or recolor a reminder list. Identify the list by id or name.',
  inputSchema: {
    type: 'object',
    properties: {
      id: {
        type: 'string',
        description: 'ID of the list to update (preferred)',
      },
      name: {
        type: 'string',
        description: 'Current name of the list to update (used when id is omitted)',
      },
      newName: {
        type: 'string',
        description: 'New name for the list',
      },
      color: {
        type: 'string',
        description: 'New list color as hex, e.g. "#FF9500"',
      },
    },
  },
};

/**
 * Handler for update_list tool
 */
export async function updateListHandler(
  args: unknown,
  executor: SwiftExecutor
): Promise<{ content: Array<{ type: string; text: string }> }> {
  const validatedArgs = validateInput(updateListSchema, args);
  const list = await executor.execute<ReminderList>('update-list', validatedArgs);

  return {
    content: [
      {
        type: 'text',
        text: `✅ Updated list: "${list.title}"\n\nID: ${list.id}${list.color ? `\nColor: ${list.color}` : ''}`,
      },
    ],
  };
}
