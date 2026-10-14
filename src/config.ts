import { randomBytes } from 'crypto';
import { readFileSync } from 'fs';

export const DEFAULT_HTTP_HOST = '0.0.0.0';
export const DEFAULT_HTTP_PORT = 3847;
export const MIN_TOKEN_LENGTH = 32;

export type ServerConfig =
  | { mode: 'stdio' }
  | { mode: 'generate-token' }
  | { mode: 'http'; host: string; port: number; token: string };

export class ConfigError extends Error {}

/**
 * Generate a random bearer token suitable for REMINDERS_MCP_TOKEN.
 */
export function generateToken(): string {
  return randomBytes(32).toString('base64url');
}

/**
 * Resolve the server configuration from CLI arguments and environment.
 *
 * CLI flags take precedence over environment variables. The token is only
 * read from the environment or a file so it never shows up in `ps` output.
 *
 *   --http                     Serve MCP over HTTP instead of stdio
 *   --host <addr>              Bind address (default 0.0.0.0)
 *   --port <n>                 Port (default 3847)
 *   --generate-token           Print a new random token and exit
 *
 *   REMINDERS_MCP_TRANSPORT    "stdio" (default) or "http"
 *   REMINDERS_MCP_HOST         Bind address
 *   REMINDERS_MCP_PORT         Port
 *   REMINDERS_MCP_TOKEN        Bearer token (required for HTTP, or use
 *   REMINDERS_MCP_TOKEN_FILE   a file containing it)
 */
export function parseConfig(argv: string[], env: NodeJS.ProcessEnv): ServerConfig {
  let http = env.REMINDERS_MCP_TRANSPORT === 'http';
  let host = env.REMINDERS_MCP_HOST || DEFAULT_HTTP_HOST;
  let portRaw = env.REMINDERS_MCP_PORT;

  if (env.REMINDERS_MCP_TRANSPORT && !['stdio', 'http'].includes(env.REMINDERS_MCP_TRANSPORT)) {
    throw new ConfigError(
      `REMINDERS_MCP_TRANSPORT must be "stdio" or "http", got "${env.REMINDERS_MCP_TRANSPORT}"`
    );
  }

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const value = () => {
      const next = argv[++i];
      if (next === undefined || next.startsWith('--')) {
        throw new ConfigError(`${arg} requires a value`);
      }
      return next;
    };

    switch (arg) {
      case '--http':
        http = true;
        break;
      case '--stdio':
        http = false;
        break;
      case '--host':
        host = value();
        break;
      case '--port':
        portRaw = value();
        break;
      case '--generate-token':
        return { mode: 'generate-token' };
      default:
        throw new ConfigError(`Unknown argument: ${arg}`);
    }
  }

  if (!http) return { mode: 'stdio' };

  const port = portRaw === undefined ? DEFAULT_HTTP_PORT : Number(portRaw);
  if (!Number.isInteger(port) || port < 0 || port > 65535) {
    throw new ConfigError(`Invalid port: ${portRaw}`);
  }

  const token = readToken(env);
  if (!token) {
    throw new ConfigError(
      'HTTP mode requires REMINDERS_MCP_TOKEN or REMINDERS_MCP_TOKEN_FILE. ' +
        'Generate a token with: apple-reminders-mcp --generate-token'
    );
  }
  if (token.length < MIN_TOKEN_LENGTH) {
    throw new ConfigError(
      `REMINDERS_MCP_TOKEN must be at least ${MIN_TOKEN_LENGTH} characters. ` +
        'Generate one with: apple-reminders-mcp --generate-token'
    );
  }

  return { mode: 'http', host, port, token };
}

function readToken(env: NodeJS.ProcessEnv): string | undefined {
  if (env.REMINDERS_MCP_TOKEN) return env.REMINDERS_MCP_TOKEN.trim();
  if (!env.REMINDERS_MCP_TOKEN_FILE) return undefined;

  try {
    return readFileSync(env.REMINDERS_MCP_TOKEN_FILE, 'utf8').trim();
  } catch (error) {
    throw new ConfigError(
      `Could not read REMINDERS_MCP_TOKEN_FILE (${env.REMINDERS_MCP_TOKEN_FILE}): ` +
        (error instanceof Error ? error.message : String(error))
    );
  }
}
