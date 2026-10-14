import Foundation
import RemindersKit

/// Command router - routes CLI commands to appropriate handlers
class CommandRouter {
    private let reminderManager = ReminderManager()
    private let listManager = ListManager()
    
    /// Route a command with JSON input
    func route(command: String, jsonInput: String) async throws -> String {
        switch command {
        case "create-reminder":
            return try await handleCreateReminder(jsonInput: jsonInput)
        case "get-reminder":
            return try await handleGetReminder(jsonInput: jsonInput)
        case "update-reminder":
            return try await handleUpdateReminder(jsonInput: jsonInput)
        case "list-reminders":
            return try await handleListReminders(jsonInput: jsonInput)
        case "search-reminders":
            return try await handleSearchReminders(jsonInput: jsonInput)
        case "get-todays-reminders":
            return try await handleGetTodaysReminders()
        case "get-overdue-reminders":
            return try await handleGetOverdueReminders()
        case "get-completed-reminders":
            return try await handleGetCompletedReminders(jsonInput: jsonInput)
        case "complete-reminder":
            return try await handleCompleteReminder(jsonInput: jsonInput)
        case "uncomplete-reminder":
            return try await handleUncompleteReminder(jsonInput: jsonInput)
        case "delete-reminder":
            return try await handleDeleteReminder(jsonInput: jsonInput)
        case "get-all-lists":
            return try handleGetAllLists()
        case "create-list":
            return try handleCreateList(jsonInput: jsonInput)
        case "update-list":
            return try handleUpdateList(jsonInput: jsonInput)
        case "delete-list":
            return try await handleDeleteList(jsonInput: jsonInput)
        default:
            throw CLIError(
                code: "UNKNOWN_COMMAND",
                message: "Unknown command: \(command)"
            )
        }
    }
    
    // MARK: - Command Handlers
    
    private func handleCreateReminder(jsonInput: String) throws -> String {
        let input = try decodeInput(CreateReminderInput.self, from: jsonInput)
        let reminder = try reminderManager.createReminder(input: input)
        let response = CLIResponse(success: true, data: reminder)
        return try encodeResponse(response)
    }
    
    private func handleGetReminder(jsonInput: String) throws -> String {
        struct GetReminderInput: Codable {
            let id: String
        }
        
        let input = try decodeInput(GetReminderInput.self, from: jsonInput)
        
        guard let reminder = try reminderManager.getReminder(id: input.id) else {
            throw ReminderError.reminderNotFound(input.id)
        }
        
        let response = CLIResponse(success: true, data: reminder)
        return try encodeResponse(response)
    }
    
    private func handleListReminders(jsonInput: String) async throws -> String {
        struct ListRemindersInput: Codable {
            let completed: Bool?
        }
        
        let input = try decodeInput(ListRemindersInput.self, from: jsonInput)
        let reminders = try await reminderManager.getAllReminders(completed: input.completed)
        let response = CLIResponse(success: true, data: reminders)
        return try encodeResponse(response)
    }
    
    private func handleUpdateReminder(jsonInput: String) throws -> String {
        // Own type (not CreateReminderInput): dueDate and recurrence tell "absent" from "null"
        let input = try decodeInput(UpdateReminderInput.self, from: jsonInput)
        let reminder = try reminderManager.updateReminder(id: input.id, input: input)
        let response = CLIResponse(success: true, data: reminder)
        return try encodeResponse(response)
    }
    
    private func handleCompleteReminder(jsonInput: String) throws -> String {
        struct CompleteReminderInput: Codable {
            let id: String
        }
        
        let input = try decodeInput(CompleteReminderInput.self, from: jsonInput)
        let result = try reminderManager.completeReminder(id: input.id)
        let response = CLIResponse(success: true, data: result)
        return try encodeResponse(response)
    }
    
    private func handleUncompleteReminder(jsonInput: String) throws -> String {
        struct UncompleteReminderInput: Codable {
            let id: String
        }
        
        let input = try decodeInput(UncompleteReminderInput.self, from: jsonInput)
        let result = try reminderManager.uncompleteReminder(id: input.id)
        let response = CLIResponse(success: true, data: result)
        return try encodeResponse(response)
    }
    
    private func handleDeleteReminder(jsonInput: String) throws -> String {
        struct DeleteReminderInput: Codable {
            let id: String
        }
        
        let input = try decodeInput(DeleteReminderInput.self, from: jsonInput)
        try reminderManager.deleteReminder(id: input.id)
        
        struct DeleteResponse: Codable {
            let deleted: Bool
            let id: String
        }
        
        let response = CLIResponse(success: true, data: DeleteResponse(deleted: true, id: input.id))
        return try encodeResponse(response)
    }
    
    private func handleGetAllLists() throws -> String {
        let lists = listManager.getAllLists()
        let response = CLIResponse(success: true, data: lists)
        return try encodeResponse(response)
    }
    
    private func handleCreateList(jsonInput: String) throws -> String {
        let input = try decodeInput(CreateListInput.self, from: jsonInput)
        let list = try listManager.createList(input: input)
        let response = CLIResponse(success: true, data: list)
        return try encodeResponse(response)
    }
    
    private func handleUpdateList(jsonInput: String) throws -> String {
        let input = try decodeInput(UpdateListInput.self, from: jsonInput)
        let list = try listManager.updateList(input: input)
        let response = CLIResponse(success: true, data: list)
        return try encodeResponse(response)
    }
    
    private func handleDeleteList(jsonInput: String) async throws -> String {
        struct DeleteListInput: Codable {
            let id: String?
            let name: String?
        }
        
        let input = try decodeInput(DeleteListInput.self, from: jsonInput)
        let result = try await listManager.deleteList(id: input.id, name: input.name)
        let response = CLIResponse(success: true, data: result)
        return try encodeResponse(response)
    }
    
    private func handleSearchReminders(jsonInput: String) async throws -> String {
        struct SearchInput: Codable {
            let searchText: String
            let completed: Bool?
        }
        
        let input = try decodeInput(SearchInput.self, from: jsonInput)
        let reminders = try await reminderManager.searchReminders(
            searchText: input.searchText,
            completed: input.completed
        )
        let response = CLIResponse(success: true, data: reminders)
        return try encodeResponse(response)
    }
    
    private func handleGetTodaysReminders() async throws -> String {
        let reminders = try await reminderManager.getTodaysReminders()
        let response = CLIResponse(success: true, data: reminders)
        return try encodeResponse(response)
    }
    
    private func handleGetOverdueReminders() async throws -> String {
        let reminders = try await reminderManager.getOverdueReminders()
        let response = CLIResponse(success: true, data: reminders)
        return try encodeResponse(response)
    }
    
    private func handleGetCompletedReminders(jsonInput: String) async throws -> String {
        struct CompletedInput: Codable {
            let startDate: String?
            let endDate: String?
        }
        
        let input = try decodeInput(CompletedInput.self, from: jsonInput)
        
        let formatter = ISO8601DateFormatter()
        let startDate = input.startDate.flatMap { formatter.date(from: $0) }
        let endDate = input.endDate.flatMap { formatter.date(from: $0) }
        
        let reminders = try await reminderManager.getCompletedReminders(
            startDate: startDate,
            endDate: endDate
        )
        let response = CLIResponse(success: true, data: reminders)
        return try encodeResponse(response)
    }
    
    // MARK: - Helpers
    
    private func decodeInput<T: Decodable>(_ type: T.Type, from jsonString: String) throws -> T {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw CLIError(code: "INVALID_JSON", message: "Invalid JSON input")
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            return try decoder.decode(type, from: jsonData)
        } catch {
            throw CLIError(
                code: "JSON_DECODE_ERROR",
                message: "Failed to decode JSON: \(error.localizedDescription)"
            )
        }
    }
    
    private func encodeResponse<T: Encodable>(_ response: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let jsonData = try encoder.encode(response)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw CLIError(code: "ENCODING_ERROR", message: "Failed to encode response")
        }
        
        return jsonString
    }
}

/// CLI Error type
struct CLIError: Error, CustomStringConvertible {
    let code: String
    let message: String
    
    var description: String {
        return message
    }
}

