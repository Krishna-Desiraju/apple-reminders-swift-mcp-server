import { mkdtempSync, writeFileSync } from 'fs';
import { tmpdir } from 'os';
import path from 'path';
import { describe, expect, it } from 'vitest';
import {
  ConfigError,
  DEFAULT_HTTP_HOST,
  DEFAULT_HTTP_PORT,
  generateToken,
  MIN_TOKEN_LENGTH,
  parseConfig,
} from '../../src/config.js';

const TOKEN = 'x'.repeat(MIN_TOKEN_LENGTH);

describe('parseConfig', () => {
  it('defaults to stdio', () => {
    expect(parseConfig([], {})).toEqual({ mode: 'stdio' });
  });

  it('enables HTTP on all interfaces by default', () => {
    expect(parseConfig(['--http'], { REMINDERS_MCP_TOKEN: TOKEN })).toEqual({
      mode: 'http',
      host: DEFAULT_HTTP_HOST,
      port: DEFAULT_HTTP_PORT,
      token: TOKEN,
    });
  });

  it('reads HTTP settings from the environment', () => {
    const config = parseConfig([], {
      REMINDERS_MCP_TRANSPORT: 'http',
      REMINDERS_MCP_HOST: '192.168.1.10',
      REMINDERS_MCP_PORT: '9000',
      REMINDERS_MCP_TOKEN: TOKEN,
    });
    expect(config).toEqual({ mode: 'http', host: '192.168.1.10', port: 9000, token: TOKEN });
  });

  it('lets flags override the environment', () => {
    const config = parseConfig(['--host', '127.0.0.1', '--port', '4000'], {
      REMINDERS_MCP_TRANSPORT: 'http',
      REMINDERS_MCP_HOST: '192.168.1.10',
      REMINDERS_MCP_PORT: '9000',
      REMINDERS_MCP_TOKEN: TOKEN,
    });
    expect(config).toMatchObject({ host: '127.0.0.1', port: 4000 });
    expect(parseConfig(['--stdio'], { REMINDERS_MCP_TRANSPORT: 'http' })).toEqual({
      mode: 'stdio',
    });
  });

  it('refuses HTTP without a token', () => {
    expect(() => parseConfig(['--http'], {})).toThrow(/REMINDERS_MCP_TOKEN/);
  });

  it('reads the token from a file', () => {
    const file = path.join(mkdtempSync(path.join(tmpdir(), 'reminders-mcp-')), 'token');
    writeFileSync(file, `${TOKEN}\n`);
    expect(parseConfig(['--http'], { REMINDERS_MCP_TOKEN_FILE: file })).toMatchObject({
      token: TOKEN,
    });
    expect(() => parseConfig(['--http'], { REMINDERS_MCP_TOKEN_FILE: `${file}-missing` })).toThrow(
      /Could not read REMINDERS_MCP_TOKEN_FILE/
    );
  });

  it('refuses a short token', () => {
    expect(() => parseConfig(['--http'], { REMINDERS_MCP_TOKEN: 'short' })).toThrow(
      /at least 32 characters/
    );
  });

  it('rejects bad ports, unknown flags, and missing values', () => {
    const env = { REMINDERS_MCP_TOKEN: TOKEN };
    expect(() => parseConfig(['--http', '--port', 'abc'], env)).toThrow(ConfigError);
    expect(() => parseConfig(['--http', '--port', '70000'], env)).toThrow(ConfigError);
    expect(() => parseConfig(['--http', '--host'], env)).toThrow(/requires a value/);
    expect(() => parseConfig(['--verbose'], env)).toThrow(/Unknown argument/);
    expect(() => parseConfig([], { REMINDERS_MCP_TRANSPORT: 'sse' })).toThrow(ConfigError);
  });

  it('supports --generate-token', () => {
    expect(parseConfig(['--generate-token'], {})).toEqual({ mode: 'generate-token' });
  });
});

describe('generateToken', () => {
  it('produces unique tokens long enough to pass validation', () => {
    const a = generateToken();
    const b = generateToken();
    expect(a).not.toEqual(b);
    expect(a.length).toBeGreaterThanOrEqual(MIN_TOKEN_LENGTH);
  });
});
