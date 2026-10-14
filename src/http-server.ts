import { createHash, timingSafeEqual } from 'crypto';
import http, { IncomingMessage, ServerResponse } from 'http';
import { AddressInfo } from 'net';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { SwiftExecutor } from './executor/swift-executor.js';
import { createServer } from './server.js';

export const MCP_PATH = '/mcp';
export const MAX_BODY_BYTES = 1024 * 1024;

export interface HttpServerOptions {
  host: string;
  port: number;
  token: string;
  executor: SwiftExecutor;
  /** Failed auth attempts allowed per IP within the window before lockout. */
  maxAuthFailures?: number;
  authFailureWindowMs?: number;
  log?: (message: string) => void;
}

class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string
  ) {
    super(message);
  }
}

/**
 * Tracks failed authentication attempts per client IP and locks an IP out
 * once it exceeds the limit within the window.
 */
class AuthFailureLimiter {
  private failures = new Map<string, { count: number; windowStart: number }>();

  constructor(
    private readonly maxFailures: number,
    private readonly windowMs: number
  ) {}

  /** Milliseconds until the IP may retry, or 0 if it isn't locked out. */
  lockedFor(ip: string, now = Date.now()): number {
    const entry = this.failures.get(ip);
    if (!entry) return 0;
    const elapsed = now - entry.windowStart;
    if (elapsed >= this.windowMs) {
      this.failures.delete(ip);
      return 0;
    }
    return entry.count >= this.maxFailures ? this.windowMs - elapsed : 0;
  }

  recordFailure(ip: string, now = Date.now()): void {
    const entry = this.failures.get(ip);
    if (!entry || now - entry.windowStart >= this.windowMs) {
      this.failures.set(ip, { count: 1, windowStart: now });
    } else {
      entry.count++;
    }
  }

  reset(ip: string): void {
    this.failures.delete(ip);
  }
}

function digest(value: string): Buffer {
  return createHash('sha256').update(value).digest();
}

function sendJson(res: ServerResponse, status: number, body: unknown, headers = {}): void {
  res.writeHead(status, { 'Content-Type': 'application/json', ...headers });
  res.end(JSON.stringify(body));
}

function sendRpcError(res: ServerResponse, status: number, message: string, headers = {}): void {
  // JSON-RPC server error code; clients surface `message` to the user.
  sendJson(res, status, { jsonrpc: '2.0', error: { code: -32000, message }, id: null }, headers);
}

async function readJsonBody(req: IncomingMessage): Promise<unknown> {
  const declared = Number(req.headers['content-length']);
  if (declared > MAX_BODY_BYTES) throw new HttpError(413, 'Request body too large');

  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw new HttpError(413, 'Request body too large');
    chunks.push(chunk);
  }

  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw new HttpError(400, 'Invalid JSON body');
  }
}

/** Log tool calls so there's a record of what remote clients did. */
function auditToolCalls(body: unknown, ip: string, log: (message: string) => void): void {
  const messages = Array.isArray(body) ? body : [body];
  for (const message of messages) {
    if (message?.method === 'tools/call') {
      log(`[http] ${ip} tools/call ${message.params?.name ?? '(unnamed)'}`);
    }
  }
}

/**
 * Serve the MCP server over Streamable HTTP, protected by a bearer token.
 *
 * Runs in stateless mode: every POST gets a fresh Server and transport, which
 * fits these tools since none of them hold state between calls.
 */
export async function startHttpServer(options: HttpServerOptions): Promise<http.Server> {
  const { token, executor } = options;
  const log = options.log ?? ((message: string) => console.error(message));
  const limiter = new AuthFailureLimiter(
    options.maxAuthFailures ?? 10,
    options.authFailureWindowMs ?? 15 * 60 * 1000
  );
  const tokenDigest = digest(token);

  const isAuthorized = (req: IncomingMessage): boolean => {
    const match = /^Bearer\s+(.+)$/i.exec(req.headers.authorization ?? '');
    // Compare fixed-length digests so neither length nor content leaks via timing.
    return match !== null && timingSafeEqual(digest(match[1].trim()), tokenDigest);
  };

  const handle = async (req: IncomingMessage, res: ServerResponse) => {
    const ip = req.socket.remoteAddress ?? 'unknown';
    const { pathname } = new URL(req.url ?? '/', 'http://localhost');

    if (pathname !== MCP_PATH) {
      sendJson(res, 404, { error: 'Not found' });
      return;
    }

    const lockedMs = limiter.lockedFor(ip);
    if (lockedMs > 0) {
      sendRpcError(res, 429, 'Too many failed authentication attempts', {
        'Retry-After': String(Math.ceil(lockedMs / 1000)),
      });
      return;
    }

    if (!isAuthorized(req)) {
      limiter.recordFailure(ip);
      log(`[http] ${ip} rejected: invalid or missing bearer token`);
      sendRpcError(res, 401, 'Unauthorized', { 'WWW-Authenticate': 'Bearer' });
      return;
    }
    limiter.reset(ip);

    // Stateless mode has no SSE stream to open (GET) or session to end (DELETE).
    if (req.method !== 'POST') {
      sendRpcError(res, 405, 'Method not allowed', { Allow: 'POST' });
      return;
    }

    const body = await readJsonBody(req);
    auditToolCalls(body, ip, log);

    const server = createServer(executor);
    const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
    res.on('close', () => {
      void transport.close();
      void server.close();
    });
    await server.connect(transport);
    await transport.handleRequest(req, res, body);
  };

  const httpServer = http.createServer((req, res) => {
    handle(req, res).catch((error) => {
      if (res.headersSent) {
        res.end();
        return;
      }
      if (error instanceof HttpError) {
        sendRpcError(res, error.status, error.message);
        return;
      }
      log(`[http] internal error: ${error instanceof Error ? error.message : String(error)}`);
      sendRpcError(res, 500, 'Internal server error');
    });
  });

  await new Promise<void>((resolve, reject) => {
    httpServer.once('error', reject);
    httpServer.listen(options.port, options.host, () => {
      httpServer.off('error', reject);
      resolve();
    });
  });

  const address = httpServer.address() as AddressInfo;
  log(
    `Apple Reminders MCP Server listening on http://${address.address}:${address.port}${MCP_PATH}`
  );
  return httpServer;
}
