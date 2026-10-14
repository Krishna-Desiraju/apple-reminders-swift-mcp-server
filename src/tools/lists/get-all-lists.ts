import { SwiftExecutor } from '../../executor/swift-executor.js';
import type { ReminderList } from '../../types/list.js';
import type { Tool } from '@modelcontextprotocol/sdk/types.js';

/**
 * Tool definition for get_all_lists
 */
export const getAllListsTool: Tool = {
  name: 'get_all_lists',
  description: 'Get all reminder lists (calendars)',
  inputSchema: {
    type: 'object',
    properties: {},
  },
};

/**
 * Handler for get_all_lists tool
 */
export async function getAllListsHandler(
  _args: unknown,
  executor: SwiftExecutor
): Promise<{ content: Array<{ type: string; text: string }> }> {
  // Execute Swift CLI (no args needed)
  const lists = await executor.execute<ReminderList[]>('get-all-lists', {});

  // Format response
  if (lists.length === 0) {
    return {
      content: [
        {
          type: 'text',
          text: 'No reminder lists found.',
        },
      ],
    };
  }

  const listsList = lists
    .map((list, index) => {
      const account = list.source ? ` | Account: ${list.source}` : '';
      return `${index + 1}. ${list.title}\n   Type: ${list.type}${account} | ID: ${list.id}`;
    })
    .join('\n\n');

  const responseText = `Found ${lists.length} list(s):\n\n${listsList}`;

  return {
    content: [
      {
        type: 'text',
        text: responseText,
      },
    ],
  };
}
