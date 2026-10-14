#!/usr/bin/env node

import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { ConfigError, generateToken, parseConfig } from './config.js';
import { SwiftExecutor } from './executor/swift-executor.js';
import { startHttpServer } from './http-server.js';
import { createServer } from './server.js';

async function main() {
  const config = parseConfig(process.argv.slice(2), process.env);

  if (config.mode === 'generate-token') {
    console.log(generateToken());
    return;
  }

  // Initialize Swift executor
  const swiftExecutor = new SwiftExecutor();

  if (config.mode === 'http') {
    await startHttpServer({ ...config, executor: swiftExecutor });
    return;
  }

  // Connect to transport (stdio)
  const server = createServer(swiftExecutor);
  const transport = new StdioServerTransport();
  await server.connect(transport);

  // Log to stderr (stdout is used for MCP protocol)
  console.error('Apple Reminders MCP Server v0.2.0 running on stdio');
  console.error('Available tools: 12 (CRUD, search, lists, date-based queries)');
}

// Run the server
main().catch((error) => {
  if (error instanceof ConfigError) {
    console.error(`Error: ${error.message}`);
    process.exit(2);
  }
  console.error('Fatal error:', error);
  process.exit(1);
});
