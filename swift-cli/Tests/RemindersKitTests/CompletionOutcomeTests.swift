import Foundation
import Testing
@testable import RemindersKit

// Pure logic only: nothing here touches an event store or requests access.

private func snapshot(rules: Bool, completed: Bool) -> CompletionSnapshot {
    CompletionSnapshot(hasRecurrenceRules: rules, isCompleted: completed)
}

@Suite("classifyCompletion")
struct ClassifyCompletionTests {
    @Test("no rule, completed after the save: completed")
    func noRule() {
        let outcome = classifyCompletion(
            before: snapshot(rules: false, completed: false), after: snapshot(rules: false, completed: true))
        #expect(outcome == .completed)
    }

    @Test("rule, open after the save: advanced")
    func ruleAndOpen() {
        let outcome = classifyCompletion(
            before: snapshot(rules: true, completed: false), after: snapshot(rules: true, completed: false))
        #expect(outcome == .advanced)
    }

    @Test("rule, completed after the save: lastOccurrence")
    func ruleAndCompleted() {
        let outcome = classifyCompletion(
            before: snapshot(rules: true, completed: false), after: snapshot(rules: true, completed: true))
        #expect(outcome == .lastOccurrence)
    }

    @Test("rule gone after the save but completed: still lastOccurrence")
    func ruleGoneAfterSave() {
        let outcome = classifyCompletion(
            before: snapshot(rules: true, completed: false), after: snapshot(rules: false, completed: true))
        #expect(outcome == .lastOccurrence)
    }

    @Test("completing a reminder that was already completed is classified by its rule")
    func alreadyCompletedBefore() {
        #expect(
            classifyCompletion(
                before: snapshot(rules: false, completed: true), after: snapshot(rules: false, completed: true))
                == .completed)
        #expect(
            classifyCompletion(
                before: snapshot(rules: true, completed: true), after: snapshot(rules: true, completed: true))
                == .lastOccurrence)
    }
}

@Suite("decideUncomplete")
struct DecideUncompleteTests {
    @Test("recurring and open: alreadyOpen, nothing to change")
    func recurringOpen() {
        #expect(decideUncomplete(hasRecurrenceRules: true, isCompleted: false) == .alreadyOpen)
    }

    @Test("recurring and completed (last occurrence): reopened")
    func recurringCompleted() {
        #expect(decideUncomplete(hasRecurrenceRules: true, isCompleted: true) == .reopened)
    }

    @Test("completed copy (completed, no rule): reopened")
    func completedCopy() {
        #expect(decideUncomplete(hasRecurrenceRules: false, isCompleted: true) == .reopened)
    }

    @Test("not recurring and already open: reopened, as before")
    func plainOpen() {
        #expect(decideUncomplete(hasRecurrenceRules: false, isCompleted: false) == .reopened)
    }
}

private let reminder = Reminder(
    id: "ID-1", title: "Gym", isCompleted: false, listId: "L", listName: "Personal",
    hasRecurrenceRules: true,
    recurrence: .supported(RecurrenceRule(frequency: .weekly, interval: 1, occurrenceCount: 3)),
    dueDateHasTime: true)

private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Suite("Completion response encoding")
struct CompletionEncodingTests {
    @Test("complete result: reminder, outcome and previousDueDate as ISO 8601")
    func completeResult() throws {
        let previous = try #require(ISO8601DateFormatter().date(from: "2026-10-12T14:30:00Z"))
        let object = try json(
            CompleteReminderResult(reminder: reminder, outcome: .advanced, previousDueDate: previous))
        #expect(Set(object.keys) == ["reminder", "outcome", "previousDueDate"])
        #expect(object["outcome"] as? String == "advanced")
        #expect(object["previousDueDate"] as? String == "2026-10-12T14:30:00Z")
        let nested = try #require(object["reminder"] as? [String: Any])
        #expect(nested["id"] as? String == "ID-1")
        #expect(nested["dueDateHasTime"] as? Bool == true)
    }

    @Test("outcome names are the wire values")
    func outcomeNames() throws {
        for (outcome, name) in [
            (CompleteOutcome.completed, "completed"),
            (.advanced, "advanced"),
            (.lastOccurrence, "lastOccurrence"),
        ] {
            let object = try json(CompleteReminderResult(reminder: reminder, outcome: outcome, previousDueDate: nil))
            #expect(object["outcome"] as? String == name)
        }
    }

    @Test("no previous due date is written as null")
    func previousDueDateNull() throws {
        let object = try json(
            CompleteReminderResult(reminder: reminder, outcome: .completed, previousDueDate: nil))
        #expect(object.keys.contains("previousDueDate"))
        #expect(object["previousDueDate"] is NSNull)
    }

    @Test("uncomplete result: reminder and outcome")
    func uncompleteResult() throws {
        for (outcome, name) in [(UncompleteOutcome.reopened, "reopened"), (.alreadyOpen, "alreadyOpen")] {
            let object = try json(UncompleteReminderResult(reminder: reminder, outcome: outcome))
            #expect(Set(object.keys) == ["reminder", "outcome"])
            #expect(object["outcome"] as? String == name)
            #expect((object["reminder"] as? [String: Any])?["title"] as? String == "Gym")
        }
    }
}
