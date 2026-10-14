import type { Server } from 'http';
import type { AddressInfo } from 'net';
import { afterEach, describe, expect, it } from 'vitest';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import type { SwiftExecutor } from '../../src/executor/swift-executor.js';
import { MAX_BODY_BYTES, startHttpServer } from '../../src/http-server.js';

const TOKEN = 'test-token-0123456789abcdef0123456789';

// Stands in for the Swift CLI so tests don't need Reminders access.
const fakeExecutor = { execute: async () => [] } as unknown as SwiftExecutor;

let server: Server | undefined;
let logs: string[] = [];

async function start(options: { maxAuthFailures?: number } = {}): Promise<string> {
  logs = [];
  server = await startHttpServer({
    host: '127.0.0.1',
    port: 0,
    token: TOKEN,
    executor: fakeExecutor,
    log: (message) => logs.push(message),
    ...options,
  });
  const { port } = server.address() as AddressInfo;
  return `http://127.0.0.1:${port}`;
}

async function connect(baseUrl: string, token = TOKEN): Promise<Client> {
  const client = new Client({ name: 'test', version: '1.0.0' });
  const transport = new StreamableHTTPClientTransport(new URL(`${baseUrl}/mcp`), {
    requestInit: { headers: { Authorization: `Bearer ${token}` } },
  });
  await client.connect(transport);
  return client;
}

function post(baseUrl: string, body: string, headers: Record<string, string> = {}) {
  return fetch(`${baseUrl}/mcp`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json, text/event-stream',
      ...headers,
    },
    body,
  });
}

afterEach(async () => {
  await new Promise((resolve) => server?.close(resolve));
  server = undefined;
});

describe('HTTP transport', () => {
  it('serves tools to a client with a valid token', async () => {
    const client = await connect(await start());
    const { tools } = await client.listTools();
    expect(tools.map((t) => t.name)).toContain('create_reminder');
    await client.close();
  });

  it('runs tool calls and logs them', async () => {
    const client = await connect(await start());
    const result = await client.callTool({ name: 'get_all_lists', arguments: {} });
    expect(result.content).toEqual([{ type: 'text', text: 'No reminder lists found.' }]);
    expect(logs.some((line) => /127\.0\.0\.1 tools\/call get_all_lists/.test(line))).toBe(true);
    await client.close();
  });

  it('rejects a missing token', async () => {
    const res = await post(await start(), '{}');
    expect(res.status).toBe(401);
    expect(res.headers.get('www-authenticate')).toBe('Bearer');
  });

  it('rejects a wrong token', async () => {
    const baseUrl = await start();
    await expect(connect(baseUrl, 'wrong-token')).rejects.toThrow();
    const res = await post(baseUrl, '{}', { Authorization: `Bearer ${TOKEN}x` });
    expect(res.status).toBe(401);
  });

  it('locks out an IP after repeated failures, even with the right token', async () => {
    const baseUrl = await start({ maxAuthFailures: 3 });
    for (let i = 0; i < 3; i++) {
      expect((await post(baseUrl, '{}', { Authorization: 'Bearer nope' })).status).toBe(401);
    }
    const res = await post(baseUrl, '{}', { Authorization: `Bearer ${TOKEN}` });
    expect(res.status).toBe(429);
    expect(Number(res.headers.get('retry-after'))).toBeGreaterThan(0);
  });

  it('only serves POST on /mcp', async () => {
    const baseUrl = await start();
    const auth = { Authorization: `Bearer ${TOKEN}` };
    expect((await fetch(`${baseUrl}/mcp`, { headers: auth })).status).toBe(405);
    expect((await fetch(`${baseUrl}/other`, { headers: auth })).status).toBe(404);
  });

  it('rejects oversized and malformed bodies', async () => {
    const baseUrl = await start();
    const auth = { Authorization: `Bearer ${TOKEN}` };
    const big = JSON.stringify({ padding: 'x'.repeat(MAX_BODY_BYTES) });
    expect((await post(baseUrl, big, auth)).status).toBe(413);
    expect((await post(baseUrl, 'not json', auth)).status).toBe(400);
  });
});
