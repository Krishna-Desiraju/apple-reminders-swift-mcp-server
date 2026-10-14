import Foundation

/// What completing a reminder did.
///
/// - `completed`: a reminder that doesn't repeat is now completed.
/// - `advanced`: a recurring reminder moved to its next occurrence and is still open (EventKit
///   leaves a completed copy behind under a new ID).
/// - `lastOccurrence`: a recurring reminder had no next occurrence, so it is completed for good.
public enum CompleteOutcome: String, Codable, Equatable {
    case completed
    case advanced
    case lastOccurrence
}

/// What `complete-reminder` has to know about a reminder to classify a save.
public struct CompletionSnapshot: Equatable {
    public let hasRecurrenceRules: Bool
    public let isCompleted: Bool

    public init(hasRecurrenceRules: Bool, isCompleted: Bool) {
        self.hasRecurrenceRules = hasRecurrenceRules
        self.isCompleted = isCompleted
    }
}

/// Classify the result of saving a reminder with `isCompleted = true`. Pure: no event store.
///
/// | Before  | After     | Outcome          |
/// |---------|-----------|------------------|
/// | no rule | any       | `completed`      |
/// | rule    | open      | `advanced`       |
/// | rule    | completed | `lastOccurrence` |
///
/// Only the open/completed state of the saved reminder is compared, not its due date: an
/// advance always moves the due date forward, so the date adds no information.
public func classifyCompletion(before: CompletionSnapshot, after: CompletionSnapshot) -> CompleteOutcome {
    guard before.hasRecurrenceRules else { return .completed }
    return after.isCompleted ? .lastOccurrence : .advanced
}

/// The `data` of a `complete-reminder` response.
public struct CompleteReminderResult: Codable {
    /// The reminder after the save. For `advanced` this is the same reminder, back to open with
    /// its due date moved to the next occurrence and the count-based end decremented.
    public let reminder: Reminder
    public let outcome: CompleteOutcome
    /// The due date before the save (ISO 8601), or null when there was none. Whether it had a
    /// time is `reminder.dueDateHasTime`: completing never changes that.
    public let previousDueDate: Date?

    public init(reminder: Reminder, outcome: CompleteOutcome, previousDueDate: Date?) {
        self.reminder = reminder
        self.outcome = outcome
        self.previousDueDate = previousDueDate
    }

    private enum CodingKeys: String, CodingKey {
        case reminder, outcome, previousDueDate
    }

    /// `previousDueDate` is written as null (not left out) when there was none.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reminder, forKey: .reminder)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(previousDueDate, forKey: .previousDueDate)
    }
}

/// What `uncomplete-reminder` did.
///
/// - `reopened`: the reminder is open again (a completed copy, a reminder completed at its last
///   occurrence, or one that doesn't repeat).
/// - `alreadyOpen`: a recurring reminder that was already open; nothing was changed or saved.
public enum UncompleteOutcome: String, Codable, Equatable {
    case reopened
    case alreadyOpen
}

/// Decide what uncompleting does. A recurring reminder that is open has already advanced past
/// the occurrence that was completed; there is no undo for that, so it is left alone.
public func decideUncomplete(hasRecurrenceRules: Bool, isCompleted: Bool) -> UncompleteOutcome {
    hasRecurrenceRules && !isCompleted ? .alreadyOpen : .reopened
}

/// The `data` of an `uncomplete-reminder` response.
public struct UncompleteReminderResult: Codable {
    /// The reminder after the call. For `alreadyOpen` it is unchanged, due date included.
    public let reminder: Reminder
    public let outcome: UncompleteOutcome

    public init(reminder: Reminder, outcome: UncompleteOutcome) {
        self.reminder = reminder
        self.outcome = outcome
    }
}
