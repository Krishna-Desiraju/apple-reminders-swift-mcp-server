import { execFileSync } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';
import { MCPError, MCPErrorCode, mapSwiftErrorCode, SwiftCLIError } from '../types/error.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

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
  private timeout: number;

  constructor(options: SwiftExecutorOptions = {}) {
    // Default to release build for better performance
    this.cliPath =
      options.cliPath || path.join(__dirname, '../../swift-cli/.build/release/reminders-cli');
    this.timeout = options.timeout || 30000; // 30 seconds default
  }

  /**
   * Execute a Swift CLI command
   */
  async execute<T>(command: string, args: unknown = {}): Promise<T> {
    const jsonInput = JSON.stringify(args);

    try {
      // Pass argv directly rather than building a shell string: reminder titles
      // routinely contain apostrophes, which break shell quoting.
      const result = execFileSync(this.cliPath, [command, jsonInput], {
        encoding: 'utf-8',
        timeout: this.timeout,
        stdio: ['pipe', 'pipe', 'pipe'],
      });

      const response = JSON.parse(result) as SwiftCLIResponse<T>;

      if (!response.success || response.error) {
        throw this.createMCPError(response.error);
      }

      if (!response.data) {
        throw new MCPError(MCPErrorCode.INTERNAL_ERROR, 'Swift CLI returned success but no data');
      }

      return response.data;
    } catch (error) {
      // Handle execution errors
      if (error instanceof MCPError) {
        throw error;
      }

      if (error && typeof error === 'object' && 'stderr' in error) {
        const stderr = (error as { stderr: Buffer | string }).stderr.toString();
        try {
          // Try to parse error JSON from stderr
          const errorResponse = JSON.parse(stderr) as SwiftCLIResponse<T>;
          if (errorResponse.error) {
            throw this.createMCPError(errorResponse.error);
          }
        } catch (parseError) {
          // If we can't parse stderr, throw a generic error
          throw new MCPError(
            MCPErrorCode.SWIFT_CLI_EXECUTION_FAILED,
            `Swift CLI execution failed: ${stderr}`,
            { stderr }
          );
        }
      }

      // Generic error
      throw new MCPError(
        MCPErrorCode.INTERNAL_ERROR,
        error instanceof Error ? error.message : 'Unknown error',
        { originalError: error }
      );
    }
  }

  /**
   * Request access to reminders (must be called first)
   */
  async requestAccess(): Promise<{ granted: boolean; message: string }> {
    try {
      const result = execFileSync(this.cliPath, ['request-access'], {
        encoding: 'utf-8',
        timeout: this.timeout,
        stdio: ['pipe', 'pipe', 'pipe'],
      });

      return JSON.parse(result);
    } catch (error) {
      throw new MCPError(MCPErrorCode.PERMISSION_DENIED, 'Failed to request access to reminders', {
        originalError: error,
      });
    }
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
