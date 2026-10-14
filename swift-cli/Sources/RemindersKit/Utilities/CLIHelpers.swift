import Foundation

/// CLI response structure
public struct CLIResponse<T: Codable>: Codable {
    public let success: Bool
    public let data: T?
    public let error: CLIError?
    
    public init(success: Bool, data: T? = nil, error: CLIError? = nil) {
        self.success = success
        self.data = data
        self.error = error
    }
}

/// CLI error structure
public struct CLIError: Codable {
    public let code: String
    public let message: String
    public let details: String?
    
    public init(code: String, message: String, details: String? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }
}

/// Pretty JSON encoder for CLI output
extension JSONEncoder {
    public static func prettyPrinter() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

/// Print JSON response and exit
public func printResponse<T: Codable>(_ response: CLIResponse<T>) -> Never {
    let encoder = JSONEncoder.prettyPrinter()
    
    do {
        let jsonData = try encoder.encode(response)
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        }
        exit(response.success ? 0 : 1)
    } catch {
        print("""
        {
          "success": false,
          "error": {
            "code": "ENCODING_ERROR",
            "message": "Failed to encode response: \(error.localizedDescription)"
          }
        }
        """)
        exit(1)
    }
}

/// Print error and exit
public func printError(_ error: Error) -> Never {
    let cliError: CLIError
    
    if let reminderError = error as? ReminderError {
        cliError = CLIError(
            code: errorCodeForReminderError(reminderError),
            message: reminderError.description
        )
    } else {
        cliError = CLIError(
            code: "INTERNAL_ERROR",
            message: error.localizedDescription
        )
    }
    
    let response = CLIResponse<String>(success: false, error: cliError)
    printResponse(response)
}

/// Map ReminderError to error code
private func errorCodeForReminderError(_ error: ReminderError) -> String {
    switch error {
    case .listNotFound:
        return "LIST_NOT_FOUND"
    case .noDefaultList:
        return "NO_DEFAULT_LIST"
    case .reminderNotFound:
        return "REMINDER_NOT_FOUND"
    case .invalidDateFormat:
        return "INVALID_DATE_FORMAT"
    case .permissionDenied:
        return "PERMISSION_DENIED"
    case .ambiguousList:
        return "AMBIGUOUS_LIST"
    case .listNotModifiable:
        return "LIST_NOT_MODIFIABLE"
    case .sourceNotFound:
        return "SOURCE_NOT_FOUND"
    case .invalidInput:
        return "INVALID_INPUT"
    }
}

/// Import ReminderError from ReminderManager
import EventKit

