import { describe, it, expect, afterEach } from 'vitest';
import { existsSync, rmSync } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { tmpdir } from 'os';
import { SwiftExecutor } from '../../src/executor/swift-executor.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/// Stands in for reminders-cli and reports the argv it actually received, so
/// these tests observe the process boundary rather than trusting it.
const ECHO_CLI = path.join(__dirname, '../fixtures/echo-cli.mjs');

interface EchoResult {
  argv: string[];
}

function executor(): SwiftExecutor {
  return new SwiftExecutor({ cliPath: ECHO_CLI });
}

/// Recover the payload the CLI would have parsed.
async function payloadFor(args: unknown): Promise<Record<string, unknown>> {
  const result = await executor().execute<EchoResult>('create-reminder', args);
  return JSON.parse(result.argv[1]);
}

describe('SwiftExecutor argument passing', () => {
  it('passes the command and payload as separate argv entries', async () => {
    const result = await executor().execute<EchoResult>('create-reminder', { title: 'Buy milk' });

    expect(result.argv).toHaveLength(2);
    expect(result.argv[0]).toBe('create-reminder');
    expect(JSON.parse(result.argv[1])).toEqual({ title: 'Buy milk' });
  });

  it('sends exactly one argument for request-access', async () => {
    // requestAccess builds its own call and must not pick up a stray payload.
    // Unlike execute(), it returns the CLI's raw JSON without unwrapping
    // `data`, because request-access reports {granted, message} at top level.
    const result = (await executor().requestAccess()) as unknown as {
      data: EchoResult;
    };
    expect(result.data.argv).toEqual(['request-access']);
  });

  // The bug that started this: arguments used to be interpolated into a shell
  // string wrapped in single quotes, so an apostrophe ended the quoting.
  describe('shell metacharacters survive intact', () => {
    it('handles an apostrophe, the everyday case', async () => {
      const payload = await payloadFor({ title: "Call Bob's dentist" });
      expect(payload.title).toBe("Call Bob's dentist");
    });

    it('handles double quotes', async () => {
      const payload = await payloadFor({ title: 'Read "Dune"' });
      expect(payload.title).toBe('Read "Dune"');
    });

    it.each([
      ['semicolon', 'a; b'],
      ['pipe', 'a | b'],
      ['ampersand', 'a && b'],
      ['backtick', 'a `b` c'],
      ['command substitution', 'a $(b) c'],
      ['variable expansion', 'cost is $HOME'],
      ['redirect', 'a > b'],
      ['glob', 'notes/*.txt'],
      ['newline', 'line one\nline two'],
      ['backslash', 'C:\\path\\to'],
      ['mixed quotes', `it's a "test" \`now\``],
    ])('handles %s', async (_label, title) => {
      const payload = await payloadFor({ title });
      expect(payload.title).toBe(title);
    });

    it('preserves unicode and emoji', async () => {
      const payload = await payloadFor({ title: 'Café ☕ 日本語' });
      expect(payload.title).toBe('Café ☕ 日本語');
    });
  });

  describe('injection attempts are inert', () => {
    const marker = path.join(tmpdir(), 'swift-executor-injection-probe');

    afterEach(() => {
      rmSync(marker, { force: true });
    });

    // A model summarising untrusted text could be talked into creating a
    // reminder with a title like this. It must reach EventKit as literal text.
    it('does not execute an injected command', async () => {
      const title = `'; touch ${marker}; echo '`;
      const payload = await payloadFor({ title });

      expect(payload.title).toBe(title);
      expect(existsSync(marker)).toBe(false);
    });

    it('does not execute command substitution', async () => {
      const title = `$(touch ${marker})`;
      const payload = await payloadFor({ title });

      expect(payload.title).toBe(title);
      expect(existsSync(marker)).toBe(false);
    });

    it('does not execute a backtick subshell', async () => {
      const title = `\`touch ${marker}\``;
      const payload = await payloadFor({ title });

      expect(payload.title).toBe(title);
      expect(existsSync(marker)).toBe(false);
    });

    it('keeps injected content in the field it belongs to', async () => {
      const payload = await payloadFor({
        title: "'; rm -rf /tmp/nothing; echo '",
        notes: 'ordinary notes',
      });

      expect(payload.title).toBe("'; rm -rf /tmp/nothing; echo '");
      expect(payload.notes).toBe('ordinary notes');
    });
  });
});
