import EventKit
import Foundation

/// What an update does to one field: leave it, clear it, or set it.
///
/// On the wire: key absent = `.unchanged`, `null` = `.cleared`, a value = `.set`.
public enum FieldUpdate<Value> {
    case unchanged
    case cleared
    case set(Value)
}

extension FieldUpdate: Equatable where Value: Equatable {}

extension KeyedDecodingContainer {
    /// Tell a missing key from an explicit `null`, which `decodeIfPresent` can't do.
    fileprivate func decodeFieldUpdate<Value: Decodable>(
        _ type: Value.Type, forKey key: Key
    ) throws -> FieldUpdate<Value> {
        guard contains(key) else { return .unchanged }
        if try decodeNil(forKey: key) { return .cleared }
        return .set(try decode(type, forKey: key))
    }
}

/// Input model for updating a reminder.
///
/// `dueDate` and `recurrence` are tri-state. The other optional fields keep the old full-replace
/// behaviour (omitting `notes` or `url` clears them), which is out of scope here.
public struct UpdateReminderInput: Decodable {
    public let id: String
    public let title: String
    public let notes: String?
    public let listName: String?
    public let dueDate: FieldUpdate<String> // ISO 8601 format
    public let priority: Int?
    public let flagged: Bool?
    public let url: String?
    public let tags: [String]?
    public let recurrence: FieldUpdate<RecurrenceRule>

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, listName, dueDate, priority, flagged, url, tags, recurrence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        listName = try container.decodeIfPresent(String.self, forKey: .listName)
        dueDate = try container.decodeFieldUpdate(String.self, forKey: .dueDate)
        priority = try container.decodeIfPresent(Int.self, forKey: .priority)
        flagged = try container.decodeIfPresent(Bool.self, forKey: .flagged)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        recurrence = try container.decodeFieldUpdate(RecurrenceRule.self, forKey: .recurrence)
    }
}

/// The due-date rules for an update (spec §3.2), as pure functions so they can be tested
/// without an event store.
public enum UpdateDueDateRules {
    /// Why the update would leave the reminder with a rule but no due date, or nil if it's fine.
    ///
    /// Works on the resulting state: the rule survives unless `recurrence` is cleared, and the
    /// due date survives unless `dueDate` is cleared. An unsupported rule counts as a rule that
    /// stays, because an omitted `recurrence` never touches it.
    public static func violation(
        currentlyHasRules: Bool,
        currentlyHasDueDate: Bool,
        recurrence: FieldUpdate<RecurrenceRule>,
        dueDate: FieldUpdate<String>,
        title: String
    ) -> String? {
        let hasRule: Bool
        switch recurrence {
        case .unchanged: hasRule = currentlyHasRules
        case .cleared: hasRule = false
        case .set: hasRule = true
        }
        let hasDueDate: Bool
        switch dueDate {
        case .unchanged: hasDueDate = currentlyHasDueDate
        case .cleared: hasDueDate = false
        case .set: hasDueDate = true
        }
        guard hasRule, !hasDueDate else { return nil }
        return missingDueDateMessage(recurrence: recurrence, title: title)
    }

    /// The message for EventKit's "A repeating reminder must have a due date." save error
    /// (`EKErrorDomain` code 18), or nil for any other error.
    public static func message(
        forSaveError error: Error,
        recurrence: FieldUpdate<RecurrenceRule>,
        title: String
    ) -> String? {
        let nsError = error as NSError
        guard nsError.domain == EKErrorDomain,
            nsError.code == EKError.Code.recurringReminderRequiresDueDate.rawValue
        else { return nil }
        return missingDueDateMessage(recurrence: recurrence, title: title)
    }

    /// A rule being added or replaced needs a first occurrence; a rule that stays needs the
    /// due date kept (or the rule removed as well).
    private static func missingDueDateMessage(
        recurrence: FieldUpdate<RecurrenceRule>, title: String
    ) -> String {
        if case .set = recurrence {
            return RecurrenceRule.needsDueDateMessage
        }
        return "\"\(title)\" repeats, so it needs a due date. To stop it repeating too, also pass recurrence: null."
    }
}
