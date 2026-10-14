import { SwiftExecutor } from '../../executor/swift-executor.js';
import { deleteListSchema } from '../../validation/list-schemas.js';
import { validateInput } from '../../validation/reminder-schemas.js';
import type { DeleteListResult } from '../../types/list.js';
import type { Tool } from '@modelcontextprotocol/sdk/types.js';

/**
 * Tool definition for delete_list
 */
export const deleteListTool: Tool = {
  name: 'delete_list',
  description:
    'Permanently delete a reminder list AND every reminder in it. Identify the list by id or name.',
  inputSchema: {
    type: 'object',
    properties: {
      id: {
        type: 'string',
        description: 'ID of the list to delete (preferred)',
      },
      name: {
        type: 'string',
        description: 'Name of the list to delete (used when id is omitted)',
      },
    },
  },
};

/**
 * Handler for delete_list tool
 */
export async function deleteListHandler(
  args: unknown,
  executor: SwiftExecutor
): Promise<{ content: Array<{ type: string; text: string }> }> {
  const validatedArgs = validateInput(deleteListSchema, args);
  const result = await executor.execute<DeleteListResult>('delete-list', validatedArgs);

  return {
    content: [
      {
        type: 'text',
        text: `✅ Deleted list: "${result.title}" (${result.remindersDeleted} reminder(s) removed)\n\nID: ${result.id}`,
      },
    ],
  };
}
