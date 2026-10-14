import EventKit
import Foundation
import Testing
@testable import RemindersKit

// Pure logic only: nothing here touches an event store or requests access.

private func decode(_ json: String) throws -> UpdateReminderInput {
    try JSONDecoder().decode(UpdateReminderInput.self, from: Data(json.utf8))
}

private let weekly = RecurrenceRule(frequency: .weekly, interval: 1, daysOfWeek: ["monday"])

@Suite("UpdateReminderInput decoding")
struct UpdateReminderInputDecodingTests {
    @Test("a rename carries neither dueDate nor recurrence")
    func renameLeavesBothUnchanged() throws {
        let input = try decode(#"{"id":"A","title":"Gym"}"#)
        #expect(input.id == "A")
        #expect(input.title == "Gym")
        #expect(input.dueDate == .unchanged)
        #expect(input.recurrence == .unchanged)
    }

    @Test("dueDate: absent is unchanged, null is cleared, a string is set")
    func dueDateTriState() throws {
        #expect(try decode(#"{"id":"A","title":"T"}"#).dueDate == .unchanged)
        #expect(try decode(#"{"id":"A","title":"T","dueDate":null}"#).dueDate == .cleared)
        #expect(
            try decode(#"{"id":"A","title":"T","dueDate":"2026-10-19T14:30:00.000Z"}"#).dueDate
                == .set("2026-10-19T14:30:00.000Z"))
    }

    @Test("recurrence: absent is unchanged, null is cleared, an object is set")
    func recurrenceTriState() throws {
        #expect(try decode(#"{"id":"A","title":"T"}"#).recurrence == .unchanged)
        #expect(try decode(#"{"id":"A","title":"T","recurrence":null}"#).recurrence == .cleared)
        let input = try decode(
            #"{"id":"A","title":"T","recurrence":{"frequency":"weekly","interval":1,"daysOfWeek":["monday"]}}"#)
        #expect(input.recurrence == .set(weekly))
    }

    @Test("the two fields are independent")
    func fieldsAreIndependent() throws {
        let input = try decode(#"{"id":"A","title":"T","dueDate":null,"recurrence":null}"#)
        #expect(input.dueDate == .cleared)
        #expect(input.recurrence == .cleared)

        let onlyRule = try decode(#"{"id":"A","title":"T","recurrence":null}"#)
        #expect(onlyRule.dueDate == .unchanged)
    }

    @Test("other fields decode as before")
    func otherFieldsDecode() throws {
        let input = try decode(
            #"{"id":"A","title":"T","notes":"n","listName":"L","priority":5,"flagged":true,"url":"https://example.com","tags":["a"]}"#)
        #expect(input.notes == "n")
        #expect(input.listName == "L")
        #expect(input.priority == 5)
        #expect(input.url == "https://example.com")
        #expect(input.tags == ["a"])
    }

    @Test("a wrongly typed dueDate is a decode error, not 'cleared'")
    func wrongTypeFails() {
        #expect(throws: (any Error).self) { try decode(#"{"id":"A","title":"T","dueDate":5}"#) }
    }
}

@Suite("Update due-date rules")
struct UpdateDueDateRulesTests {
    private let needsDueDate = "A recurring reminder needs a due date: pass dueDate as the first occurrence."
    private let repeatsMessage =
        "\"Gym\" repeats, so it needs a due date. To stop it repeating too, also pass recurrence: null."

    private func violation(
        hasRules: Bool,
        hasDueDate: Bool,
        recurrence: FieldUpdate<RecurrenceRule> = .unchanged,
        dueDate: FieldUpdate<String> = .unchanged
    ) -> String? {
        UpdateDueDateRules.violation(
            currentlyHasRules: hasRules,
            currentlyHasDueDate: hasDueDate,
            recurrence: recurrence,
            dueDate: dueDate,
            title: "Gym")
    }

    @Test("adding a rule to a reminder with no due date is rejected")
    func addRuleWithoutDueDate() {
        #expect(violation(hasRules: false, hasDueDate: false, recurrence: .set(weekly)) == needsDueDate)
    }

    @Test("replacing a rule on a reminder with no due date is rejected")
    func replaceRuleWithoutDueDate() {
        #expect(violation(hasRules: true, hasDueDate: false, recurrence: .set(weekly)) == needsDueDate)
    }

    @Test("adding a rule while clearing the due date is rejected as needing a due date")
    func addRuleAndClearDueDate() {
        #expect(
            violation(hasRules: false, hasDueDate: true, recurrence: .set(weekly), dueDate: .cleared)
                == needsDueDate)
    }

    @Test("adding a rule with a due date in the same update is valid")
    func addRuleWithDueDate() {
        #expect(
            violation(hasRules: false, hasDueDate: false, recurrence: .set(weekly), dueDate: .set("2026-10-19T14:30:00Z"))
                == nil)
    }

    @Test("adding a rule to a reminder that already has a due date is valid")
    func addRuleToDatedReminder() {
        #expect(violation(hasRules: false, hasDueDate: true, recurrence: .set(weekly)) == nil)
    }

    @Test("clearing the due date while the rule stays is rejected, naming the title")
    func clearDueDateKeepsRule() {
        #expect(violation(hasRules: true, hasDueDate: true, dueDate: .cleared) == repeatsMessage)
    }

    @Test("clearing the due date of a reminder with an unsupported rule is rejected too")
    func clearDueDateKeepsUnsupportedRule() {
        // An unsupported rule is a rule the update leaves alone: recurrence is omitted
        #expect(violation(hasRules: true, hasDueDate: true, recurrence: .unchanged, dueDate: .cleared) == repeatsMessage)
    }

    @Test("clearing the due date and the rule together is valid")
    func clearBoth() {
        #expect(violation(hasRules: true, hasDueDate: true, recurrence: .cleared, dueDate: .cleared) == nil)
    }

    @Test("clearing only the rule is valid, and keeps the due date")
    func clearRuleOnly() {
        #expect(violation(hasRules: true, hasDueDate: true, recurrence: .cleared) == nil)
    }

    @Test("clearing the due date of a one-off reminder is valid")
    func clearDueDateOfOneOff() {
        #expect(violation(hasRules: false, hasDueDate: true, dueDate: .cleared) == nil)
    }

    @Test("setting a new due date on a recurring reminder is valid")
    func setDueDateOnRecurring() {
        #expect(violation(hasRules: true, hasDueDate: true, dueDate: .set("2026-10-20T09:00:00Z")) == nil)
    }

    @Test("an update that omits both fields never complains, whatever the reminder looks like")
    func omittedBothIsValid() {
        #expect(violation(hasRules: true, hasDueDate: true) == nil)
        #expect(violation(hasRules: false, hasDueDate: true) == nil)
        #expect(violation(hasRules: false, hasDueDate: false) == nil)
    }

    @Test("the message uses the resulting title")
    func messageUsesTitle() {
        let message = UpdateDueDateRules.violation(
            currentlyHasRules: true, currentlyHasDueDate: true,
            recurrence: .unchanged, dueDate: .cleared, title: "Pay rent")
        #expect(message == "\"Pay rent\" repeats, so it needs a due date. To stop it repeating too, also pass recurrence: null.")
    }
}

@Suite("EventKit error 18 mapping")
struct RecurringReminderRequiresDueDateMappingTests {
    private func error(domain: String = EKErrorDomain, code: Int = 18) -> NSError {
        NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: "A repeating reminder must have a due date."])
    }

    @Test("code 18 with a rule being set maps to the needs-a-due-date message")
    func mapsWhenAddingRule() {
        let message = UpdateDueDateRules.message(forSaveError: error(), recurrence: .set(weekly), title: "Gym")
        #expect(message == RecurrenceRule.needsDueDateMessage)
    }

    @Test("code 18 with the rule left alone maps to the repeats message")
    func mapsWhenRuleStays() {
        let message = UpdateDueDateRules.message(forSaveError: error(), recurrence: .unchanged, title: "Gym")
        #expect(message == "\"Gym\" repeats, so it needs a due date. To stop it repeating too, also pass recurrence: null.")
    }

    @Test("the error code is EKError.recurringReminderRequiresDueDate")
    func codeIsEighteen() {
        #expect(EKError.Code.recurringReminderRequiresDueDate.rawValue == 18)
    }

    @Test("other EventKit codes and other domains are not mapped")
    func ignoresOtherErrors() {
        #expect(UpdateDueDateRules.message(forSaveError: error(code: 17), recurrence: .unchanged, title: "Gym") == nil)
        #expect(UpdateDueDateRules.message(forSaveError: error(domain: NSCocoaErrorDomain), recurrence: .unchanged, title: "Gym") == nil)
        struct Other: Error {}
        #expect(UpdateDueDateRules.message(forSaveError: Other(), recurrence: .unchanged, title: "Gym") == nil)
    }
}

@Suite("Applying an update to a reminder")
struct ApplyUpdateTests {
    private func reminder(rules: [EKRecurrenceRule], due: DateComponents? = DateComponents(year: 2026, month: 10, day: 19)) -> EKReminder {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.title = "Gym"
        reminder.dueDateComponents = due
        if !rules.isEmpty { reminder.recurrenceRules = rules }
        return reminder
    }

    /// Two rules and a week-of-year rule are unsupported recurrence rules
    private var unsupportedRules: [EKRecurrenceRule] {
        [
            EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil),
            EKRecurrenceRule(
                recurrenceWith: .yearly, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: nil,
                monthsOfTheYear: nil, weeksOfTheYear: [10], daysOfTheYear: nil, setPositions: nil, end: nil),
        ]
    }

    @Test("an omitted recurrence leaves an unsupported rule untouched")
    func omittedKeepsUnsupportedRules() throws {
        let rules = unsupportedRules
        let ek = reminder(rules: rules)
        #expect(ReminderRecurrence.from(rules: ek.recurrenceRules).map { if case .unsupported = $0 { true } else { false } } == true)

        let before = ReminderRecurrence.from(rules: ek.recurrenceRules)

        try ReminderManager.applyRecurrence(.unchanged, to: ek)

        // By value: EventKit doesn't always hand back the same rule objects, so `===` is flaky
        #expect(ek.recurrenceRules?.count == 2)
        #expect(ReminderRecurrence.from(rules: ek.recurrenceRules) == before)
    }

    @Test("an omitted recurrence leaves a supported rule untouched")
    func omittedKeepsSupportedRule() throws {
        let rule = EKRecurrenceRule(recurrenceWith: .daily, interval: 3, end: nil)
        let ek = reminder(rules: [rule])
        try ReminderManager.applyRecurrence(.unchanged, to: ek)
        #expect(ek.recurrenceRules?.count == 1)
        #expect(ek.recurrenceRules?[0] === rule)
    }

    @Test("a null recurrence removes every rule, unsupported ones included")
    func clearedRemovesRules() throws {
        let ek = reminder(rules: unsupportedRules)
        try ReminderManager.applyRecurrence(.cleared, to: ek)
        #expect(ek.hasRecurrenceRules == false)
        #expect(ek.recurrenceRules?.isEmpty ?? true)
    }

    @Test("a recurrence object replaces the rules with exactly one rule")
    func setReplacesWithOneRule() throws {
        let ek = reminder(rules: unsupportedRules)
        try ReminderManager.applyRecurrence(.set(weekly), to: ek)
        #expect(ek.recurrenceRules?.count == 1)
        #expect(ek.recurrenceRules?.first?.frequency == .weekly)
    }

    @Test("an invalid recurrence object is rejected and leaves the rules alone")
    func invalidRuleRejected() {
        let rules = unsupportedRules
        let ek = reminder(rules: rules)
        let bad = RecurrenceRule(frequency: .daily, interval: 0)
        #expect(throws: ReminderError.self) { try ReminderManager.applyRecurrence(.set(bad), to: ek) }
        #expect(ek.recurrenceRules?.count == 2)
    }

    @Test("an omitted dueDate keeps the due date; null clears it; a value sets it")
    func dueDateTriState() {
        let ek = reminder(rules: [])
        let before = ek.dueDateComponents
        ReminderManager.applyDueDate(.unchanged, parsed: nil, to: ek)
        #expect(ek.dueDateComponents == before)

        ReminderManager.applyDueDate(.cleared, parsed: nil, to: ek)
        #expect(ek.dueDateComponents == nil)

        let date = Date(timeIntervalSince1970: 1_800_000_000)
        ReminderManager.applyDueDate(.set("ignored"), parsed: date, to: ek)
        #expect(ek.dueDateComponents?.year != nil)
        #expect(ek.dueDateComponents?.hour != nil)
    }
}
