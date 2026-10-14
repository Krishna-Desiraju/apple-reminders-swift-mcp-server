import Foundation
import RemindersKit

// Entry point for the CLI
// Note: Using top-level await instead of @main for async support
Task {
    await RemindersCLI.run()
}

// Keep the run loop alive
RunLoop.main.run()

struct RemindersCLI {
    static func run() async {
        // Parse command-line arguments
        let args = CommandLine.arguments
        
        // Need at least: program name + command
        guard args.count >= 2 else {
            printUsageAndExit()
        }
        
        let command = args[1]
        
        // Special case: request-access command
        if command == "request-access" {
            await handleRequestAccess()
            return
        }
        
        // Get JSON input (optional, defaults to empty object)
        let jsonInput = args.count >= 3 ? args[2] : "{}"
        
        // Route the command
        let router = CommandRouter()
        
        do {
            let result = try await router.route(command: command, jsonInput: jsonInput)
            print(result)
            exit(0)
        } catch let error as ReminderError {
            printErrorAndExit(code: mapReminderErrorCode(error), message: error.description)
        } catch {
            printErrorAndExit(code: "INTERNAL_ERROR", message: error.localizedDescription)
        }
    }
    
    // MARK: - Special Handlers
    
    static func handleRequestAccess() async {
        let bridge = EventKitBridge.shared
        
        do {
            let granted = try await bridge.requestAccess()
            
            struct AccessResponse: Codable {
                let granted: Bool
                let message: String
            }
            
            let response: AccessResponse
            if granted {
                response = AccessResponse(
                    granted: true,
                    message: "Access to reminders granted"
                )
            } else {
                response = AccessResponse(
                    granted: false,
                    message: "Access to reminders denied. Please grant permission in System Settings > Privacy & Security > Reminders"
                )
            }
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(response)
            
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
            
            exit(granted ? 0 : 1)
        } catch {
            printErrorAndExit(code: "PERMISSION_ERROR", message: error.localizedDescription)
        }
    }
    
    // MARK: - Helpers
    
    static func printUsageAndExit() -> Never {
        print("""
        Apple Reminders CLI
        
        Usage: reminders-cli <command> [json-input]
        
        Commands:
          request-access              Request permission to access reminders
          create-reminder <json>      Create a new reminder
          get-reminder <json>         Get a reminder by ID
          list-reminders <json>       List all reminders
          complete-reminder <json>    Mark a reminder as complete
          delete-reminder <json>      Delete a reminder
          get-all-lists               Get all reminder lists
          create-list <json>          Create a reminder list
          update-list <json>          Rename or recolor a reminder list
          delete-list <json>          Delete a list and all its reminders
        
        Examples:
          reminders-cli request-access
          reminders-cli create-reminder '{"title":"Buy milk"}'
          reminders-cli get-reminder '{"id":"x-apple-reminder://ABC123"}'
          reminders-cli list-reminders '{"completed":false}'
          reminders-cli create-list '{"name":"Groceries","color":"#34C759"}'
        """)
        exit(1)
    }
    
    static func printErrorAndExit(code: String, message: String) -> Never {
        struct ErrorResponse: Codable {
            let success: Bool
            let error: ErrorDetail
        }
        
        struct ErrorDetail: Codable {
            let code: String
            let message: String
        }
        
        let response = ErrorResponse(
            success: false,
            error: ErrorDetail(code: code, message: message)
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        if let jsonData = try? encoder.encode(response),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        } else {
            print("""
            {
              "success": false,
              "error": {
                "code": "\(code)",
                "message": "\(message)"
              }
            }
            """)
        }
        
        exit(1)
    }
    
    static func mapReminderErrorCode(_ error: ReminderError) -> String {
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
}

