import { SwiftExecutor } from '../../executor/swift-executor.js';
import type { Tool } from '@modelcontextprotocol/sdk/types.js';

export const requestAccessTool: Tool = {
  name: 'request_access',
  description:
    'Trigger the macOS prompt for Reminders access. Call this once before using other tools if access has not yet been granted. macOS will only show the prompt while a properly entitled host process (e.g. Claude Desktop) is the caller; if access was previously denied, the user must re-enable it via System Settings > Privacy & Security > Reminders.',
  inputSchema: {
    type: 'object',
    properties: {},
  },
};

export async function requestAccessHandler(
  _args: unknown,
  executor: SwiftExecutor
): Promise<{ content: Array<{ type: string; text: string }> }> {
  const result = await executor.requestAccess();
  return {
    content: [
      {
        type: 'text',
        text: result.granted
          ? `Access granted. ${result.message}`
          : `Access not granted. ${result.message}`,
      },
    ],
  };
}
