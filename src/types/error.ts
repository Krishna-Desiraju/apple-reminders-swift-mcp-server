/**
 * Error codes for MCP errors
 */
export enum MCPErrorCode {
  // Validation Errors (400-level)
  INVALID_INPUT = 'INVALID_INPUT',
  MISSING_REQUIRED_FIELD = 'MISSING_REQUIRED_FIELD',
  INVALID_DATE_FORMAT = 'INVALID_DATE_FORMAT',
  INVALID_PRIORITY = 'INVALID_PRIORITY',

  // Not Found Errors (404-level)
  REMINDER_NOT_FOUND = 'REMINDER_NOT_FOUND',
  LIST_NOT_FOUND = 'LIST_NOT_FOUND',
  SOURCE_NOT_FOUND = 'SOURCE_NOT_FOUND',

  // Conflict Errors (409-level)
  AMBIGUOUS_LIST = 'AMBIGUOUS_LIST',

  // Permission Errors (403-level)
  PERMISSION_DENIED = 'PERMISSION_DENIED',
  REMINDERS_ACCESS_DENIED = 'REMINDERS_ACCESS_DENIED',
  LIST_NOT_MODIFIABLE = 'LIST_NOT_MODIFIABLE',

  // System Errors (500-level)
  SWIFT_CLI_EXECUTION_FAILED = 'SWIFT_CLI_EXECUTION_FAILED',
  INTERNAL_ERROR = 'INTERNAL_ERROR',
  ENCODING_ERROR = 'ENCODING_ERROR',
  JSON_DECODE_ERROR = 'JSON_DECODE_ERROR',
}

/**
 * MCP Error class
 */
export class MCPError extends Error {
  constructor(
    public code: MCPErrorCode,
    message: string,
    public details?: Record<string, unknown>
  ) {
    super(message);
    this.name = 'MCPError';
  }

  toJSON() {
    return {
      isError: true,
      code: this.code,
      message: this.message,
      details: this.details,
    };
  }
}

/**
 * Swift CLI error response
 */
export interface SwiftCLIError {
  code: string;
  message: string;
  details?: string;
}

/**
 * Map Swift CLI error code to MCP error code
 */
export function mapSwiftErrorCode(swiftCode: string): MCPErrorCode {
  const mapping: Record<string, MCPErrorCode> = {
    LIST_NOT_FOUND: MCPErrorCode.LIST_NOT_FOUND,
    SOURCE_NOT_FOUND: MCPErrorCode.SOURCE_NOT_FOUND,
    AMBIGUOUS_LIST: MCPErrorCode.AMBIGUOUS_LIST,
    LIST_NOT_MODIFIABLE: MCPErrorCode.LIST_NOT_MODIFIABLE,
    INVALID_INPUT: MCPErrorCode.INVALID_INPUT,
    REMINDER_NOT_FOUND: MCPErrorCode.REMINDER_NOT_FOUND,
    PERMISSION_DENIED: MCPErrorCode.PERMISSION_DENIED,
    INVALID_DATE_FORMAT: MCPErrorCode.INVALID_DATE_FORMAT,
    ENCODING_ERROR: MCPErrorCode.ENCODING_ERROR,
    JSON_DECODE_ERROR: MCPErrorCode.JSON_DECODE_ERROR,
    INTERNAL_ERROR: MCPErrorCode.INTERNAL_ERROR,
  };

  return mapping[swiftCode] || MCPErrorCode.INTERNAL_ERROR;
}

