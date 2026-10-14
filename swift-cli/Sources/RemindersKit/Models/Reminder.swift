import Foundation
import EventKit

/// Represents a reminder with all its properties
/// This is our Codable model that gets serialized to/from JSON
public struct Reminder: Codable {
    public let id: String
    public let title: String
    public let notes: String?
    public let isCompleted: Bool
    public let priority: Int
    public let dueDate: Date?
    public let completionDate: Date?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let listId: String
    public let listName: String
    public let flagged: Bool
    public let url: String?
    public let hasAlarms: Bool
    public let hasRecurrenceRules: Bool
    /// The reminder's recurrence: its rule, the unsupported marker for a rule this server can't
    /// express exactly, or nil when it doesn't repeat
    public let recurrence: ReminderRecurrence?
    /// False for a date-only due date
    public let dueDateHasTime: Bool
    
    private enum CodingKeys: String, CodingKey {
        case id, title, notes, isCompleted, priority, dueDate, completionDate, creationDate
        case modificationDate, listId, listName, flagged, url, hasAlarms, hasRecurrenceRules
        case recurrence, dueDateHasTime
    }
    
    /// Initialize from EKReminder
    public init(from ekReminder: EKReminder) {
        self.id = ekReminder.calendarItemIdentifier
        self.title = ekReminder.title ?? ""
        self.notes = ekReminder.notes
        self.isCompleted = ekReminder.isCompleted
        self.priority = ekReminder.priority
        self.dueDate = ekReminder.dueDateComponents?.date
        self.completionDate = ekReminder.completionDate
        self.creationDate = ekReminder.creationDate
        self.modificationDate = ekReminder.lastModifiedDate
        self.listId = ekReminder.calendar?.calendarIdentifier ?? ""
        self.listName = ekReminder.calendar?.title ?? ""
        self.flagged = ekReminder.calendar?.type == .calDAV // Approximation for flagged
        self.url = ekReminder.url?.absoluteString
        self.hasAlarms = ekReminder.hasAlarms
        self.hasRecurrenceRules = ekReminder.hasRecurrenceRules
        self.recurrence = ReminderRecurrence.from(rules: ekReminder.recurrenceRules)
        self.dueDateHasTime = ekReminder.dueDateComponents?.hour != nil
    }
    
    /// Manual initializer for testing
    public init(
        id: String,
        title: String,
        notes: String? = nil,
        isCompleted: Bool = false,
        priority: Int = 0,
        dueDate: Date? = nil,
        completionDate: Date? = nil,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        listId: String,
        listName: String,
        flagged: Bool = false,
        url: String? = nil,
        hasAlarms: Bool = false,
        hasRecurrenceRules: Bool = false,
        recurrence: ReminderRecurrence? = nil,
        dueDateHasTime: Bool = false
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isCompleted = isCompleted
        self.priority = priority
        self.dueDate = dueDate
        self.completionDate = completionDate
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.listId = listId
        self.listName = listName
        self.flagged = flagged
        self.url = url
        self.hasAlarms = hasAlarms
        self.hasRecurrenceRules = hasRecurrenceRules
        self.recurrence = recurrence
        self.dueDateHasTime = dueDateHasTime
    }
    
    /// Same as the synthesized encoding, except `recurrence` is written as null (not left out)
    /// when the reminder doesn't repeat.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(priority, forKey: .priority)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(completionDate, forKey: .completionDate)
        try container.encodeIfPresent(creationDate, forKey: .creationDate)
        try container.encodeIfPresent(modificationDate, forKey: .modificationDate)
        try container.encode(listId, forKey: .listId)
        try container.encode(listName, forKey: .listName)
        try container.encode(flagged, forKey: .flagged)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(hasAlarms, forKey: .hasAlarms)
        try container.encode(hasRecurrenceRules, forKey: .hasRecurrenceRules)
        try container.encode(recurrence, forKey: .recurrence)
        try container.encode(dueDateHasTime, forKey: .dueDateHasTime)
    }
}

/// Input model for creating a reminder
public struct CreateReminderInput: Codable {
    public let title: String
    public let notes: String?
    public let listName: String?
    public let dueDate: String? // ISO 8601 format
    public let priority: Int?
    public let flagged: Bool?
    public let url: String?
    public let tags: [String]?
    public let recurrence: RecurrenceRule?
    public let location: ReminderLocation?
    public let alarms: [ReminderAlarm]?
    
    public init(
        title: String,
        notes: String? = nil,
        listName: String? = nil,
        dueDate: String? = nil,
        priority: Int? = nil,
        flagged: Bool? = nil,
        url: String? = nil,
        tags: [String]? = nil,
        recurrence: RecurrenceRule? = nil,
        location: ReminderLocation? = nil,
        alarms: [ReminderAlarm]? = nil
    ) {
        self.title = title
        self.notes = notes
        self.listName = listName
        self.dueDate = dueDate
        self.priority = priority
        self.flagged = flagged
        self.url = url
        self.tags = tags
        self.recurrence = recurrence
        self.location = location
        self.alarms = alarms
    }
}

