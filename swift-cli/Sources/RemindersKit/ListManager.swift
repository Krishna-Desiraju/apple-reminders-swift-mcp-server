import Foundation
import EventKit

/// Input for creating a reminder list
public struct CreateListInput: Codable {
    public let name: String
    public let color: String?
    public let source: String?

    public init(name: String, color: String? = nil, source: String? = nil) {
        self.name = name
        self.color = color
        self.source = source
    }
}

/// Input for updating a reminder list. The list is identified by `id` or `name`.
public struct UpdateListInput: Codable {
    public let id: String?
    public let name: String?
    public let newName: String?
    public let color: String?

    public init(id: String? = nil, name: String? = nil, newName: String? = nil, color: String? = nil) {
        self.id = id
        self.name = name
        self.newName = newName
        self.color = color
    }
}

/// Result of deleting a reminder list
public struct DeleteListResult: Codable {
    public let deleted: Bool
    public let id: String
    public let title: String
    public let remindersDeleted: Int
}

/// Manages reminder list (calendar) operations
public class ListManager {
    private let eventStore: EKEventStore
    private let bridge: EventKitBridge

    public init(bridge: EventKitBridge = .shared) {
        self.bridge = bridge
        self.eventStore = bridge.getEventStore()
    }

    /// Get all reminder lists
    /// - Returns: Array of reminder lists
    public func getAllLists() -> [ReminderList] {
        let calendars = bridge.getAllReminderLists()
        return calendars.map { ReminderList(from: $0) }
    }

    /// Get a list by ID
    /// - Parameter id: The list identifier
    /// - Returns: The list or nil if not found
    public func getList(id: String) -> ReminderList? {
        guard let calendar = bridge.findList(byId: id) else {
            return nil
        }
        return ReminderList(from: calendar)
    }

    /// Get a list by name
    /// - Parameter name: The list name
    /// - Returns: The list or nil if not found
    public func getList(name: String) -> ReminderList? {
        guard let calendar = bridge.findList(byName: name) else {
            return nil
        }
        return ReminderList(from: calendar)
    }

    /// Create a new reminder list
    /// - Parameter input: The list creation input
    /// - Returns: The created list
    public func createList(input: CreateListInput) throws -> ReminderList {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw ReminderError.invalidInput("List name cannot be empty")
        }

        let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
        calendar.title = name
        calendar.source = try resolveSource(named: input.source)

        if let color = input.color {
            calendar.cgColor = try parseColor(color)
        }

        try eventStore.saveCalendar(calendar, commit: true)

        return ReminderList(from: calendar)
    }

    /// Rename or recolor a reminder list
    /// - Parameter input: The list update input
    /// - Returns: The updated list
    public func updateList(input: UpdateListInput) throws -> ReminderList {
        let calendar = try findList(id: input.id, name: input.name)
        try ensureModifiable(calendar)

        if let newName = input.newName {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ReminderError.invalidInput("New list name cannot be empty")
            }
            calendar.title = trimmed
        }

        if let color = input.color {
            calendar.cgColor = try parseColor(color)
        }

        try eventStore.saveCalendar(calendar, commit: true)

        return ReminderList(from: calendar)
    }

    /// Delete a reminder list and every reminder in it
    /// - Parameters:
    ///   - id: The list identifier
    ///   - name: The list name (used when `id` is nil)
    /// - Returns: What was deleted
    public func deleteList(id: String?, name: String?) async throws -> DeleteListResult {
        let calendar = try findList(id: id, name: name)
        try ensureModifiable(calendar)

        let predicate = eventStore.predicateForReminders(in: [calendar])
        let reminderCount = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders?.count ?? 0)
            }
        }

        let result = DeleteListResult(
            deleted: true,
            id: calendar.calendarIdentifier,
            title: calendar.title,
            remindersDeleted: reminderCount
        )

        try eventStore.removeCalendar(calendar, commit: true)

        return result
    }

    // MARK: - Private Helpers

    /// Find a list by ID, falling back to an unambiguous name match
    private func findList(id: String?, name: String?) throws -> EKCalendar {
        if let id = id {
            guard let calendar = bridge.findList(byId: id) else {
                throw ReminderError.listNotFound(id)
            }
            return calendar
        }

        guard let name = name else {
            throw ReminderError.invalidInput("Either id or name is required")
        }

        let matches = bridge.findLists(byName: name)
        switch matches.count {
        case 0:
            throw ReminderError.listNotFound(name)
        case 1:
            return matches[0]
        default:
            throw ReminderError.ambiguousList(name, matches.count)
        }
    }

    private func ensureModifiable(_ calendar: EKCalendar) throws {
        if calendar.isImmutable || !calendar.allowsContentModifications {
            throw ReminderError.listNotModifiable(calendar.title)
        }
    }

    private func parseColor(_ hex: String) throws -> CGColor {
        guard let color = ReminderList.cgColor(fromHex: hex) else {
            throw ReminderError.invalidInput("Invalid color: \(hex). Expected hex like #FF9500.")
        }
        return color
    }

    /// Pick the account a new list should live in.
    ///
    /// With no name, use the account of the default reminders list so new
    /// lists land where Reminders.app would put them (usually iCloud).
    private func resolveSource(named sourceName: String?) throws -> EKSource {
        if let sourceName = sourceName {
            let match = eventStore.sources.first {
                $0.title.caseInsensitiveCompare(sourceName) == .orderedSame
            }
            guard let source = match else {
                throw ReminderError.sourceNotFound(sourceName)
            }
            return source
        }

        if let source = bridge.getDefaultRemindersList()?.source {
            return source
        }
        if let source = bridge.getAllReminderLists().first?.source {
            return source
        }
        if let source = eventStore.sources.first(where: { $0.sourceType == .local }) {
            return source
        }
        throw ReminderError.sourceNotFound("default")
    }
}
