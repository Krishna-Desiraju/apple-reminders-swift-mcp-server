import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import { SwiftExecutor } from './executor/swift-executor.js';
import { MCPError, MCPErrorCode } from './types/error.js';

// Tool imports
import { createReminderTool, createReminderHandler } from './tools/reminders/create-reminder.js';
import { updateReminderTool, updateReminderHandler } from './tools/reminders/update-reminder.js';
import { getReminderTool, getReminderHandler } from './tools/reminders/get-reminder.js';
import { deleteReminderTool, deleteReminderHandler } from './tools/reminders/delete-reminder.js';
import {
  completeReminderTool,
  completeReminderHandler,
  uncompleteReminderTool,
  uncompleteReminderHandler,
} from './tools/reminders/complete-reminder.js';
import { getRemindersListTool, getRemindersListHandler } from './tools/reminders/get-reminders.js';
import { getAllListsTool, getAllListsHandler } from './tools/lists/get-all-lists.js';
import { createListTool, createListHandler } from './tools/lists/create-list.js';
import { updateListTool, updateListHandler } from './tools/lists/update-list.js';
import { deleteListTool, deleteListHandler } from './tools/lists/delete-list.js';
import { searchRemindersTool, searchRemindersHandler } from './tools/search/search-reminders.js';
import {
  getTodaysRemindersTool,
  getTodaysRemindersHandler,
  getOverdueRemindersTool,
  getOverdueRemindersHandler,
  getCompletedRemindersTool,
  getCompletedRemindersHandler,
} from './tools/search/date-based-reminders.js';
import { requestAccessTool, requestAccessHandler } from './tools/system/request-access.js';

/**
 * Create and configure the MCP server.
 *
 * Each transport connection needs its own Server instance, so the HTTP
 * transport calls this once per request while stdio calls it once.
 */
export function createServer(swiftExecutor: SwiftExecutor): Server {
  const server = new Server(
    {
      name: 'apple-reminders',
      version: '0.2.0',
    },
    {
      capabilities: {
        tools: {},
      },
    }
  );

  // Register tools/list handler
  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: [
      // Reminder CRUD
      createReminderTool,
      updateReminderTool,
      deleteReminderTool,
      completeReminderTool,
      uncompleteReminderTool,
      getReminderTool,
      getRemindersListTool,
      
      // Lists
      getAllListsTool,
      createListTool,
      updateListTool,
      deleteListTool,
      
      // Search
      searchRemindersTool,
      getTodaysRemindersTool,
      getOverdueRemindersTool,
      getCompletedRemindersTool,

      // System
      requestAccessTool,
    ],
  }));

  // Register tools/call handler
  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params;

    try {
      switch (name) {
        case 'create_reminder':
          return await createReminderHandler(args, swiftExecutor);

        case 'update_reminder':
          return await updateReminderHandler(args, swiftExecutor);

        case 'delete_reminder':
          return await deleteReminderHandler(args, swiftExecutor);

        case 'complete_reminder':
          return await completeReminderHandler(args, swiftExecutor);

        case 'uncomplete_reminder':
          return await uncompleteReminderHandler(args, swiftExecutor);

        case 'get_reminder':
          return await getReminderHandler(args, swiftExecutor);

        case 'get_reminders':
          return await getRemindersListHandler(args, swiftExecutor);

        case 'get_all_lists':
          return await getAllListsHandler(args, swiftExecutor);

        case 'create_list':
          return await createListHandler(args, swiftExecutor);

        case 'update_list':
          return await updateListHandler(args, swiftExecutor);

        case 'delete_list':
          return await deleteListHandler(args, swiftExecutor);

        case 'search_reminders':
          return await searchRemindersHandler(args, swiftExecutor);

        case 'get_todays_reminders':
          return await getTodaysRemindersHandler(args, swiftExecutor);

        case 'get_overdue_reminders':
          return await getOverdueRemindersHandler(args, swiftExecutor);

        case 'get_completed_reminders':
          return await getCompletedRemindersHandler(args, swiftExecutor);

        case 'request_access':
          return await requestAccessHandler(args, swiftExecutor);

        default:
          throw new MCPError(MCPErrorCode.INVALID_INPUT, `Unknown tool: ${name}`);
      }
    } catch (error) {
      // Handle errors
      if (error instanceof MCPError) {
        return {
          content: [
            {
              type: 'text',
              text: `Error: ${error.message}\nCode: ${error.code}`,
            },
          ],
          isError: true,
        };
      }

      // Zod validation errors
      if (error && typeof error === 'object' && 'issues' in error) {
        const zodError = error as { issues: Array<{ path: string[]; message: string }> };
        const errorMessages = zodError.issues
          .map((issue) => `${issue.path.join('.')}: ${issue.message}`)
          .join('\n');
        return {
          content: [
            {
              type: 'text',
              text: `Validation Error:\n${errorMessages}`,
            },
          ],
          isError: true,
        };
      }

      // Generic error
      return {
        content: [
          {
            type: 'text',
            text: `Internal Error: ${error instanceof Error ? error.message : 'Unknown error'}`,
          },
        ],
        isError: true,
      };
    }
  });

  return server;
}
