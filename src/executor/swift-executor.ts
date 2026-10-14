import { spawnSync } from 'child_process';
import {
  chmodSync,
  constants,
  existsSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
} from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath } from 'url';
import { MCPError, MCPErrorCode, mapSwiftErrorCode, SwiftCLIError } from '../types/error.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

interface ResolvedCli {
  binaryPath: string;
  appBundlePath?: string;
}

/**
 * Resolve the Swift CLI binary path, preferring the `RemindersCLI.app` bundle.
 *
 * macOS attributes EventKit (Reminders) access to the *responsible process*.
 * When a parent app like Claude Desktop spawns the binary directly via exec,
 * the parent stays responsible — and if the parent has no
 * `NSRemindersUsageDescription` in its Info.plist, the OS silently denies
 * access without ever showing a permission prompt.
 *
 * Wrapping the binary in an .app bundle and launching it via LaunchServices
 * (`open`) makes the bundle itself the responsible process, so its own
 * Info.plist drives the prompt. We return the bundle path alongside the
 * binary path so the executor can choose `open` over direct exec when the
 * bundle is available.
 *
 * Also tolerates a missing `.build/release` symlink and a stripped exec bit
 * (both seen with the Claude Desktop extension installer).
 */
function resolveCliPath(defaultPath: string): ResolvedCli {
  // defaultPath looks like .../swift-cli/.build/release/reminders-cli
  // Walk up three levels to reach swift-cli/, then look for the .app bundle.
  const swiftCliDir = path.dirname(path.dirname(path.dirname(defaultPath)));
  const bundleDir = path.join(swiftCliDir, 'RemindersCLI.app');
  const bundledBinary = path.join(bundleDir, 'Contents', 'MacOS', 'reminders-cli');

  if (existsSync(bundledBinary)) {
    ensureExecutable(bundledBinary);
    return { binaryPath: bundledBinary, appBundlePath: bundleDir };
  }

  // No bundle — fall back to the bare binary, with arch-specific recovery.
  let resolved = defaultPath;
  if (!existsSync(resolved)) {
    const buildDir = path.dirname(path.dirname(defaultPath));
    if (existsSync(buildDir)) {
      for (const entry of readdirSync(buildDir)) {
        const candidate = path.join(buildDir, entry, 'release', 'reminders-cli');
        if (existsSync(candidate)) {
          resolved = candidate;
          break;
        }
      }
    }
  }

  if (existsSync(resolved)) ensureExecutable(resolved);
  return { binaryPath: resolved };
}

function ensureExecutable(p: string): void {
  try {
    const mode = statSync(p).mode;
    if (!(mode & constants.S_IXUSR)) {
      chmodSync(p, mode | constants.S_IXUSR | constants.S_IXGRP | constants.S_IXOTH);
    }
  } catch {
    // best-effort; spawn will surface a clearer error if it still can't run
  }
}

/**
 * Swift CLI response structure
 */
export interface SwiftCLIResponse<T> {
  success: boolean;
  data?: T;
  error?: SwiftCLIError;
}

/**
 * Options for Swift executor
 */
export interface SwiftExecutorOptions {
  cliPath?: string;
  timeout?: number;
}

/**
 * Executes Swift CLI commands and handles responses
 */
export class SwiftExecutor {
  private cliPath: string;
  private appBundlePath?: string;
  private timeout: number;

  constructor(options: SwiftExecutorOptions = {}) {
    const defaultPath =
      options.cliPath || path.join(__dirname, '../../swift-cli/.build/release/reminders-cli');
    const resolved = resolveCliPath(defaultPath);
    this.cliPath = resolved.binaryPath;
    this.appBundlePath = resolved.appBundlePath;
    this.timeout = options.timeout || 30000; // 30 seconds default
  }

  /**
   * Execute a Swift CLI command
   */
  async execute<T>(command: string, args: unknown = {}): Promise<T> {
    const jsonInput = JSON.stringify(args);

    let stdout: string;
    let stderr: string;
    try {
      ({ stdout, stderr } = this.runCli([command, jsonInput]));
    } catch (error) {
      throw new MCPError(
        MCPErrorCode.INTERNAL_ERROR,
        error instanceof Error ? error.message : 'Unknown error',
        { originalError: error }
      );
    }

    let response: SwiftCLIResponse<T>;
    try {
      response = JSON.parse(stdout) as SwiftCLIResponse<T>;
    } catch {
      // Sometimes the CLI prints its error envelope to stderr instead.
      try {
        response = JSON.parse(stderr) as SwiftCLIResponse<T>;
      } catch {
        throw new MCPError(
          MCPErrorCode.SWIFT_CLI_EXECUTION_FAILED,
          `Swift CLI returned non-JSON output: ${stderr || stdout}`,
          { stdout, stderr }
        );
      }
    }

    if (!response.success || response.error) {
      throw this.createMCPError(response.error);
    }

    if (!response.data) {
      throw new MCPError(MCPErrorCode.INTERNAL_ERROR, 'Swift CLI returned success but no data');
    }

    return response.data;
  }

  /**
   * Request access to reminders (must be called first)
   */
  async requestAccess(): Promise<{ granted: boolean; message: string }> {
    try {
      const { stdout } = this.runCli(['request-access']);
      return JSON.parse(stdout);
    } catch (error) {
      throw new MCPError(MCPErrorCode.PERMISSION_DENIED, 'Failed to request access to reminders', {
        originalError: error,
      });
    }
  }

  /**
   * Run the Swift CLI with the given arguments and return its stdout/stderr.
   *
   * When an .app bundle is available we launch it via `open` so that
   * LaunchServices makes the bundle the responsible TCC process. `open`
   * detaches the spawned app's stdio, so we use `--stdout`/`--stderr` to
   * redirect to temp files we then read back. (Direct `exec` against the
   * bundled binary would leave the parent process — e.g. Claude Desktop —
   * responsible for TCC, which silently denies Reminders access.)
   */
  private runCli(args: string[]): { stdout: string; stderr: string } {
    if (this.appBundlePath) {
      const tmpDir = mkdtempSync(path.join(os.tmpdir(), 'reminders-cli-'));
      const stdoutFile = path.join(tmpDir, 'stdout');
      const stderrFile = path.join(tmpDir, 'stderr');
      try {
        spawnSync(
          'open',
          [
            '-W',
            '-n',
            '-a',
            this.appBundlePath,
            '--stdout',
            stdoutFile,
            '--stderr',
            stderrFile,
            '--args',
            ...args,
          ],
          { encoding: 'utf-8', timeout: this.timeout }
        );
        // `open` may print "Unable to block on application" warnings even on
        // success; we ignore its exit code in favor of the Swift CLI's JSON
        // envelope, which we read from the redirect files below.
        const stdout = existsSync(stdoutFile) ? readFileSync(stdoutFile, 'utf-8') : '';
        const stderr = existsSync(stderrFile) ? readFileSync(stderrFile, 'utf-8') : '';
        return { stdout, stderr };
      } finally {
        try {
          rmSync(tmpDir, { recursive: true, force: true });
        } catch {
          // ignore cleanup errors
        }
      }
    }

    // No bundle: direct exec. Useful for development or when running from a
    // host that already has Reminders permission (e.g. Terminal.app).
    const result = spawnSync(this.cliPath, args, {
      encoding: 'utf-8',
      timeout: this.timeout,
    });
    return {
      stdout: result.stdout?.toString() ?? '',
      stderr: result.stderr?.toString() ?? '',
    };
  }

  /**
   * Create MCPError from Swift CLI error
   */
  private createMCPError(swiftError?: SwiftCLIError): MCPError {
    if (!swiftError) {
      return new MCPError(MCPErrorCode.INTERNAL_ERROR, 'Unknown error from Swift CLI');
    }

    const mcpErrorCode = mapSwiftErrorCode(swiftError.code);
    return new MCPError(mcpErrorCode, swiftError.message, {
      swiftCode: swiftError.code,
      swiftDetails: swiftError.details,
    });
  }
}
