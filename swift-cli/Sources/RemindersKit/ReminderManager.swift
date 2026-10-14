import Foundation
import EventKit

/// Manages reminder CRUD operations using EventKit
public class ReminderManager {
    private let eventStore: EKEventStore
    private let bridge: EventKitBridge
    
    public init(bridge: EventKitBridge = .shared) {
        self.bridge = bridge
        self.eventStore = bridge.getEventStore()
    }
    
    /// Create a new reminder
    /// - Parameter input: The reminder creation input
    /// - Returns: The created reminder
    public func createReminder(input: CreateReminderInput) throws -> Reminder {
        // Validate before any EventKit call: bad rule values raise ObjC exceptions that crash the CLI
        let ekRecurrenceRule = try input.recurrence.map { rule -> EKRecurrenceRule in
            try rule.validate(dueDate: input.dueDate)
            return try rule.toEKRecurrenceRule()
        }
        
        // Create EKReminder instance
        let ekReminder = EKReminder(eventStore: eventStore)
        
        // Set basic properties
        ekReminder.title = input.title
        
        // Handle notes with tags
        if let tags = input.tags, !tags.isEmpty {
            let tagString = tags.map { "[#\($0)]" }.joined(separator: " ")
            if let notes = input.notes {
                ekReminder.notes = "\(tagString)\n\(notes)"
            } else {
                ekReminder.notes = tagString
            }
        } else {
            ekReminder.notes = input.notes
        }
        
        // Set priority (0-9 scale)
        if let priority = input.priority {
            ekReminder.priority = max(0, min(9, priority))
        }
        
        // Set due date
        if let dueDateString = input.dueDate {
            let date = try parseDateString(dueDateString)
            ekReminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: date
            )
        }
        
        // Set URL
        if let urlString = input.url {
            ekReminder.url = URL(string: urlString)
        }
        
        // Set recurrence rule
        // (replace, never append: a second rule shows in Reminders.app as a blank "Custom")
        if let ekRecurrenceRule = ekRecurrenceRule {
            ekReminder.recurrenceRules = [ekRecurrenceRule]
        }
        
        // Add alarms
        if let alarms = input.alarms {
            for alarm in alarms {
                ekReminder.addAlarm(alarm.toEKAlarm())
            }
        }
        
        // Add location-based alarm if location is provided
        if let location = input.location {
            let ekLocation = location.toEKStructuredLocation()
            let locationAlarm = EKAlarm()
            locationAlarm.structuredLocation = ekLocation
            
            // Set proximity (enter or leave)
            switch location.proximity {
            case .enter:
                locationAlarm.proximity = .enter
            case .leave:
                locationAlarm.proximity = .leave
            }
            
            ekReminder.addAlarm(locationAlarm)
        }
        
        // Find or use default calendar
        let calendar: EKCalendar
        if let listName = input.listName {
            if let foundCalendar = bridge.findList(byName: listName) {
                calendar = foundCalendar
            } else {
                throw ReminderError.listNotFound(listName)
            }
        } else {
            if let defaultCalendar = bridge.getDefaultRemindersList() {
                calendar = defaultCalendar
            } else {
                throw ReminderError.noDefaultList
            }
        }
        
        ekReminder.calendar = calendar
        
        // Save the reminder
        try eventStore.save(ekReminder, commit: true)
        
        // Return our model
        return Reminder(from: ekReminder)
    }
    
    /// Get a reminder by ID
    /// - Parameter id: The reminder identifier
    /// - Returns: The reminder or nil if not found
    public func getReminder(id: String) throws -> Reminder? {
        guard let ekReminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
            return nil
        }
        return Reminder(from: ekReminder)
    }
    
    /// Get all reminders (with optional filters)
    /// - Parameter completed: Filter by completion status (nil = all)
    /// - Returns: Array of reminders
    public func getAllReminders(completed: Bool? = nil) async throws -> [Reminder] {
        let calendars = bridge.getAllReminderLists()
        
        // Create predicate
        let predicate = eventStore.predicateForReminders(in: calendars)
        
        // Fetch reminders
        let ekReminders = try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                if let reminders = reminders {
                    continuation.resume(returning: reminders)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
        
        // Filter by completion status if specified
        let filteredReminders = if let completed = completed {
            ekReminders.filter { $0.isCompleted == completed }
        } else {
            ekReminders
        }
        
        return filteredReminders.map { Reminder(from: $0) }
    }
    
    /// Search reminders by text
    /// - Parameters:
    ///   - searchText: Text to search for in title and notes
    ///   - completed: Optional completion status filter
    /// - Returns: Array of matching reminders
    public func searchReminders(searchText: String, completed: Bool? = nil) async throws -> [Reminder] {
        let allReminders = try await getAllReminders(completed: completed)
        let lowercasedSearch = searchText.lowercased()
        
        return allReminders.filter { reminder in
            let titleMatch = reminder.title.lowercased().contains(lowercasedSearch)
            let notesMatch = reminder.notes?.lowercased().contains(lowercasedSearch) ?? false
            return titleMatch || notesMatch
        }
    }
    
    /// Get reminders due today
    /// - Returns: Array of reminders due today
    public func getTodaysReminders() async throws -> [Reminder] {
        let allReminders = try await getAllReminders(completed: false)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        return allReminders.filter { reminder in
            guard let dueDate = reminder.dueDate else { return false }
            return dueDate >= today && dueDate < tomorrow
        }
    }
    
    /// Get overdue reminders
    /// - Returns: Array of overdue reminders
    public func getOverdueReminders() async throws -> [Reminder] {
        let allReminders = try await getAllReminders(completed: false)
        let now = Date()
        
        return allReminders.filter { reminder in
            guard let dueDate = reminder.dueDate else { return false }
            return dueDate < now
        }
    }
    
    /// Get completed reminders within a date range
    /// - Parameters:
    ///   - startDate: Start date (optional)
    ///   - endDate: End date (optional)
    /// - Returns: Array of completed reminders
    public func getCompletedReminders(startDate: Date? = nil, endDate: Date? = nil) async throws -> [Reminder] {
        let allReminders = try await getAllReminders(completed: true)
        
        return allReminders.filter { reminder in
            guard let completionDate = reminder.completionDate else { return false }
            
            if let start = startDate, completionDate < start {
                return false
            }
            
            if let end = endDate, completionDate > end {
                return false
            }
            
            return true
        }
    }
    
    /// Delete a reminder
    /// - Parameter id: The reminder identifier
    public func deleteReminder(id: String) throws {
        guard let ekReminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
            throw ReminderError.reminderNotFound(id)
        }
        
        try eventStore.remove(ekReminder, commit: true)
    }
    
    /// Update an existing reminder
    ///
    /// `dueDate` and `recurrence` are tri-state: omitted leaves them alone (an omitted
    /// `recurrence` never touches `recurrenceRules`, so unsupported rules and Hourly repeats
    /// survive), `null` clears them, a value sets them. The other fields keep the full-replace
    /// behaviour.
    /// - Parameter input: The reminder update input
    /// - Returns: The updated reminder
    public func updateReminder(id: String, input: UpdateReminderInput) throws -> Reminder {
        guard let ekReminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
            throw ReminderError.reminderNotFound(id)
        }
        
        // Check everything that can fail before changing anything. Bad rule values raise ObjC
        // exceptions that crash the CLI, so the rule is validated before any EventKit call.
        if case .set(let rule) = input.recurrence {
            try rule.validate()
        }
        
        if let message = UpdateDueDateRules.violation(
            currentlyHasRules: ekReminder.hasRecurrenceRules,
            currentlyHasDueDate: ekReminder.dueDateComponents != nil,
            recurrence: input.recurrence,
            dueDate: input.dueDate,
            title: input.title
        ) {
            throw ReminderError.invalidInput(message)
        }
        
        let newDueDate: Date?
        if case .set(let dueDateString) = input.dueDate {
            newDueDate = try parseDateString(dueDateString)
        } else {
            newDueDate = nil
        }
        
        // Update title
        ekReminder.title = input.title
        
        // Update notes with tags
        if let tags = input.tags, !tags.isEmpty {
            let tagString = tags.map { "[#\($0)]" }.joined(separator: " ")
            if let notes = input.notes {
                ekReminder.notes = "\(tagString)\n\(notes)"
            } else {
                ekReminder.notes = tagString
            }
        } else {
            ekReminder.notes = input.notes
        }
        
        // Update priority
        if let priority = input.priority {
            ekReminder.priority = max(0, min(9, priority))
        }
        
        // Update recurrence, then due date (the rule goes first so a rule and its due date can be
        // cleared together)
        try Self.applyRecurrence(input.recurrence, to: ekReminder)
        Self.applyDueDate(input.dueDate, parsed: newDueDate, to: ekReminder)
        
        // Update URL
        if let urlString = input.url {
            ekReminder.url = URL(string: urlString)
        } else {
            ekReminder.url = nil
        }
        
        // Update list if specified
        if let listName = input.listName {
            if let calendar = bridge.findList(byName: listName) {
                ekReminder.calendar = calendar
            } else {
                throw ReminderError.listNotFound(listName)
            }
        }
        
        // Save the reminder
        do {
            try eventStore.save(ekReminder, commit: true)
        } catch {
            // Backstop for the due-date check above: EventKit's own "repeating reminder must
            // have a due date" error gets the same agent-readable message
            if let message = UpdateDueDateRules.message(
                forSaveError: error, recurrence: input.recurrence, title: input.title)
            {
                throw ReminderError.invalidInput(message)
            }
            throw error
        }
        
        return Reminder(from: ekReminder)
    }
    
    /// Mark a reminder as complete.
    ///
    /// Saving a recurring reminder with `isCompleted = true` makes EventKit advance it in place
    /// (same ID, open, next due date, count-based end decremented, a completed copy left behind)
    /// or, at the last occurrence, complete it. The saved object reflects that state, so the
    /// outcome is read from it right after the save.
    /// - Parameter id: The reminder identifier
    /// - Returns: The reminder after the save, how the completion played out, and the previous due date
    public func completeReminder(id: String) throws -> CompleteReminderResult {
        guard let ekReminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
            throw ReminderError.reminderNotFound(id)
        }
        
        let before = CompletionSnapshot(
            hasRecurrenceRules: ekReminder.hasRecurrenceRules, isCompleted: ekReminder.isCompleted)
        let previousDueDate = ekReminder.dueDateComponents?.date
        
        ekReminder.isCompleted = true
        ekReminder.completionDate = Date()
        
        try eventStore.save(ekReminder, commit: true)
        
        let after = CompletionSnapshot(
            hasRecurrenceRules: ekReminder.hasRecurrenceRules, isCompleted: ekReminder.isCompleted)
        return CompleteReminderResult(
            reminder: Reminder(from: ekReminder),
            outcome: classifyCompletion(before: before, after: after),
            previousDueDate: previousDueDate)
    }
    
    /// Mark a reminder as incomplete. A recurring reminder that is already open is left alone:
    /// it advanced when it was completed, and that can't be undone.
    /// - Parameter id: The reminder identifier
    /// - Returns: The reminder and whether it was reopened or was already open
    public func uncompleteReminder(id: String) throws -> UncompleteReminderResult {
        guard let ekReminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
            throw ReminderError.reminderNotFound(id)
        }
        
        let outcome = decideUncomplete(
            hasRecurrenceRules: ekReminder.hasRecurrenceRules, isCompleted: ekReminder.isCompleted)
        guard outcome == .reopened else {
            return UncompleteReminderResult(reminder: Reminder(from: ekReminder), outcome: outcome)
        }
        
        ekReminder.isCompleted = false
        ekReminder.completionDate = nil
        
        try eventStore.save(ekReminder, commit: true)
        
        return UncompleteReminderResult(reminder: Reminder(from: ekReminder), outcome: outcome)
    }
    
    // MARK: - Update helpers
    
    /// Apply the `recurrence` field of an update.
    ///
    /// Omitted leaves `recurrenceRules` alone (this is what keeps unsupported rules and Hourly
    /// repeats intact), `null` removes the rules, an object replaces them with exactly one rule.
    static func applyRecurrence(_ update: FieldUpdate<RecurrenceRule>, to ekReminder: EKReminder) throws {
        switch update {
        case .unchanged:
            break
        case .cleared:
            ekReminder.recurrenceRules = nil
        case .set(let rule):
            try rule.validate()
            // replace, never append: a second rule shows in Reminders.app as a blank "Custom"
            ekReminder.recurrenceRules = [try rule.toEKRecurrenceRule()]
        }
    }
    
    /// Apply the `dueDate` field of an update. Omitted leaves the due date alone.
    /// - Parameter parsed: The date parsed from a `.set` value
    static func applyDueDate(_ update: FieldUpdate<String>, parsed: Date?, to ekReminder: EKReminder) {
        switch update {
        case .unchanged:
            break
        case .cleared:
            ekReminder.dueDateComponents = nil
        case .set:
            guard let date = parsed else { return }
            ekReminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: date
            )
        }
    }
    
    // MARK: - Private Helpers
    
    /// Parse ISO 8601 date string
    private func parseDateString(_ dateString: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        throw ReminderError.invalidDateFormat(dateString)
    }
}

/// Errors that can occur during reminder operations
public enum ReminderError: Error, CustomStringConvertible {
    case listNotFound(String)
    case noDefaultList
    case reminderNotFound(String)
    case invalidDateFormat(String)
    case permissionDenied
    case ambiguousList(String, Int)
    case listNotModifiable(String)
    case sourceNotFound(String)
    case invalidInput(String)
    
    public var description: String {
        switch self {
        case .listNotFound(let name):
            return "List not found: \(name)"
        case .noDefaultList:
            return "No default list found"
        case .reminderNotFound(let id):
            return "Reminder not found: \(id)"
        case .invalidDateFormat(let format):
            return "Invalid date format: \(format). Expected ISO 8601."
        case .permissionDenied:
            return "Permission denied to access reminders"
        case .ambiguousList(let name, let count):
            return "\(count) lists are named \"\(name)\". Use the list ID instead."
        case .listNotModifiable(let name):
            return "List cannot be modified: \(name)"
        case .sourceNotFound(let name):
            return "Account not found: \(name)"
        case .invalidInput(let message):
            return message
        }
    }
}

