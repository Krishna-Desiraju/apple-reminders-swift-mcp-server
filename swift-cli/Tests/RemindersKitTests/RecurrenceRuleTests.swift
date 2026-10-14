import EventKit
import Foundation
import Testing
@testable import RemindersKit

// These tests build EventKit objects in memory only. They never save anything or
// request access, so they run without Reminders access.

/// The message of the error `body` throws, or nil if it doesn't throw.
private func errorMessage(_ body: () throws -> Void) -> String? {
    do {
        try body()
        return nil
    } catch let error as ReminderError {
        return error.description
    } catch {
        return "unexpected error: \(error)"
    }
}

@Suite("Weekday")
struct WeekdayTests {
    @Test("names map to EventKit raw values, 1 = Sunday through 7 = Saturday")
    func namesMapToRawValues() {
        let expected: [(String, Int)] = [
            ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4),
            ("thursday", 5), ("friday", 6), ("saturday", 7),
        ]
        for (name, rawValue) in expected {
            let weekday = Weekday(name: name)
            #expect(weekday?.ekWeekday.rawValue == rawValue)
            #expect(weekday.flatMap { Weekday(ekWeekday: $0.ekWeekday) } == weekday)
            #expect(weekday?.rawValue == name)
        }
    }

    @Test("only full lowercase names are accepted")
    func rejectsOtherSpellings() {
        for name in ["mon", "Monday", "MONDAY", "someday", "", "2"] {
            #expect(Weekday(name: name) == nil)
        }
    }
}

@Suite("RecurrenceRule to EventKit")
struct RecurrenceRuleToEventKitTests {
    @Test("daily")
    func daily() throws {
        let ekRule = try RecurrenceRule(frequency: .daily, interval: 3).toEKRecurrenceRule()

        #expect(ekRule.frequency == .daily)
        #expect(ekRule.interval == 3)
        #expect(ekRule.daysOfTheWeek == nil)
        #expect(ekRule.recurrenceEnd == nil)
    }

    @Test("weekly with weekdays")
    func weeklyWithDays() throws {
        let rule = RecurrenceRule(frequency: .weekly, interval: 2, daysOfWeek: ["monday", "wednesday"])

        let ekRule = try rule.toEKRecurrenceRule()

        #expect(ekRule.frequency == .weekly)
        #expect(ekRule.interval == 2)
        #expect(ekRule.daysOfTheWeek?.map { $0.dayOfTheWeek.rawValue } == [2, 4])
        #expect(ekRule.daysOfTheWeek?.map { $0.weekNumber } == [0, 0])
    }

    @Test("weekly without weekdays leaves the day to the due date")
    func weeklyWithoutDays() throws {
        let ekRule = try RecurrenceRule(frequency: .weekly).toEKRecurrenceRule()

        #expect(ekRule.frequency == .weekly)
        #expect(ekRule.interval == 1)
        #expect(ekRule.daysOfTheWeek == nil)
    }

    @Test("repeated weekdays are written once")
    func dedupesWeekdays() throws {
        let rule = RecurrenceRule(frequency: .weekly, daysOfWeek: ["friday", "friday"])

        #expect(try rule.toEKRecurrenceRule().daysOfTheWeek?.count == 1)
    }

    @Test("refuses an invalid rule instead of handing EventKit a value that raises")
    func refusesInvalidRule() {
        let rule = RecurrenceRule(frequency: .daily, interval: 0)

        #expect(errorMessage { _ = try rule.toEKRecurrenceRule() } != nil)
    }
}

@Suite("EventKit to RecurrenceRule")
struct RecurrenceRuleFromEventKitTests {
    @Test("daily")
    func daily() {
        let ekRule = EKRecurrenceRule(recurrenceWith: .daily, interval: 3, end: nil)

        #expect(RecurrenceRule.from(ekRule) == RecurrenceRule(frequency: .daily, interval: 3))
    }

    @Test("weekly with weekdays")
    func weeklyWithDays() {
        let ekRule = EKRecurrenceRule(
            recurrenceWith: .weekly,
            interval: 2,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday), EKRecurrenceDayOfWeek(.wednesday)],
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )

        #expect(
            RecurrenceRule.from(ekRule)
                == RecurrenceRule(frequency: .weekly, interval: 2, daysOfWeek: ["monday", "wednesday"])
        )
    }

    @Test("weekly without weekdays")
    func weeklyWithoutDays() {
        let ekRule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)

        #expect(RecurrenceRule.from(ekRule) == RecurrenceRule(frequency: .weekly))
    }

    @Test("round-trips daily and weekly rules")
    func roundTrips() throws {
        let rules = [
            RecurrenceRule(frequency: .daily),
            RecurrenceRule(frequency: .daily, interval: 5),
            RecurrenceRule(frequency: .weekly, interval: 4),
            RecurrenceRule(frequency: .weekly, daysOfWeek: ["sunday", "saturday"]),
        ]
        for rule in rules {
            #expect(RecurrenceRule.from(try rule.toEKRecurrenceRule()) == rule)
        }
    }

    @Test("rules the model can't express map to nil without crashing")
    func unmappedRulesAreNil() {
        let monday = EKRecurrenceDayOfWeek(.monday)
        let firstMonday = EKRecurrenceDayOfWeek(.monday, weekNumber: 1)
        let rules = [
            // daily with weekdays
            EKRecurrenceRule(
                recurrenceWith: .daily, interval: 1, daysOfTheWeek: [monday], daysOfTheMonth: nil,
                monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil),
            // weekly with an ordinal weekday
            EKRecurrenceRule(
                recurrenceWith: .weekly, interval: 1, daysOfTheWeek: [firstMonday], daysOfTheMonth: nil,
                monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil),
            // weekly with set positions
            EKRecurrenceRule(
                recurrenceWith: .weekly, interval: 1, daysOfTheWeek: [monday], daysOfTheMonth: nil,
                monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: [1], end: nil),
            // monthly on a day counted from the end of the month
            EKRecurrenceRule(
                recurrenceWith: .monthly, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: [-1],
                monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil),
        ]
        for rule in rules {
            #expect(RecurrenceRule.from(rule) == nil)
        }
    }
}

@Suite("RecurrenceRule validation")
struct RecurrenceRuleValidationTests {
    @Test("accepts valid daily and weekly rules")
    func acceptsValid() throws {
        try RecurrenceRule(frequency: .daily).validate()
        try RecurrenceRule(frequency: .weekly, interval: 2, daysOfWeek: ["monday"]).validate()
    }

    @Test("rejects an interval below 1")
    func rejectsBadInterval() {
        for interval in [0, -1, Int.min] {
            let message = errorMessage { try RecurrenceRule(frequency: .daily, interval: interval).validate() }
            #expect(message == "interval must be a whole number, 1 or greater")
        }
    }

    @Test("rejects unknown weekday names")
    func rejectsUnknownWeekday() {
        for name in ["mon", "Monday", "someday"] {
            let rule = RecurrenceRule(frequency: .weekly, daysOfWeek: ["tuesday", name])
            #expect(
                errorMessage { try rule.validate() }
                    == "daysOfWeek must use full lowercase weekday names: sunday, monday, tuesday, wednesday, thursday, friday, saturday"
            )
        }
    }

    @Test("rejects daysOfWeek on anything but weekly")
    func rejectsDaysOfWeekOffWeekly() {
        for frequency in [RecurrenceFrequency.daily, .monthly, .yearly] {
            let rule = RecurrenceRule(frequency: frequency, daysOfWeek: ["monday"])
            #expect(errorMessage { try rule.validate() } == "daysOfWeek only applies to weekly rules")
        }
    }

    @Test("rejects an empty daysOfWeek")
    func rejectsEmptyDaysOfWeek() {
        let rule = RecurrenceRule(frequency: .weekly, daysOfWeek: [])

        #expect(
            errorMessage { try rule.validate() }
                == "daysOfWeek can't be empty: omit it to repeat on the due date's weekday"
        )
    }

    @Test("a rule without a due date is rejected")
    func rejectsMissingDueDate() throws {
        let rule = RecurrenceRule(frequency: .weekly)

        #expect(
            errorMessage { try rule.validate(dueDate: nil) }
                == "A recurring reminder needs a due date: pass dueDate as the first occurrence."
        )
        try rule.validate(dueDate: "2026-10-19T14:30:00Z")
    }

    @Test("a bad rule is reported before the missing due date")
    func ruleErrorsComeFirst() {
        let rule = RecurrenceRule(frequency: .daily, interval: 0)

        #expect(errorMessage { try rule.validate(dueDate: nil) } == "interval must be a whole number, 1 or greater")
    }
}

@Suite("RecurrenceRule JSON")
struct RecurrenceRuleJSONTests {
    private func decode(_ json: String) throws -> RecurrenceRule {
        try JSONDecoder().decode(RecurrenceRule.self, from: Data(json.utf8))
    }

    @Test("interval defaults to 1")
    func intervalDefaults() throws {
        #expect(try decode(#"{"frequency":"daily"}"#) == RecurrenceRule(frequency: .daily))
    }

    @Test("decodes weekday names")
    func decodesWeekdays() throws {
        let rule = try decode(#"{"frequency":"weekly","interval":2,"daysOfWeek":["monday","wednesday"]}"#)

        #expect(rule == RecurrenceRule(frequency: .weekly, interval: 2, daysOfWeek: ["monday", "wednesday"]))
    }

    @Test("an unknown weekday decodes, then fails validation with a specific message")
    func unknownWeekdayFailsValidation() throws {
        let rule = try decode(#"{"frequency":"weekly","daysOfWeek":["someday"]}"#)

        #expect(errorMessage { try rule.validate() }?.hasPrefix("daysOfWeek must use full lowercase") == true)
    }

    @Test("encodes only the fields that apply")
    func encodesCompactly() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try encoder.encode(RecurrenceRule(frequency: .weekly, interval: 2, daysOfWeek: ["monday"]))

        #expect(String(decoding: json, as: UTF8.self) == #"{"daysOfWeek":["monday"],"frequency":"weekly","interval":2}"#)
    }
}

@Suite("Reminder recurrence")
struct ReminderRecurrenceTests {
    private func ekReminder(rules: [EKRecurrenceRule], due: DateComponents?) -> EKReminder {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.title = "Gym"
        reminder.dueDateComponents = due
        if !rules.isEmpty { reminder.recurrenceRules = rules }
        return reminder
    }

    private func encode(_ reminder: Reminder) throws -> [String: Any] {
        let data = try JSONEncoder().encode(reminder)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("a recurring reminder carries its rule and whether the due date has a time")
    func carriesRule() throws {
        let rule = EKRecurrenceRule(recurrenceWith: .daily, interval: 2, end: nil)
        let due = DateComponents(calendar: .current, year: 2026, month: 10, day: 19, hour: 14, minute: 30)

        let reminder = Reminder(from: ekReminder(rules: [rule], due: due))

        #expect(reminder.recurrence == .supported(RecurrenceRule(frequency: .daily, interval: 2)))
        #expect(reminder.hasRecurrenceRules)
        #expect(reminder.dueDateHasTime)
    }

    @Test("a date-only due date has no time")
    func dateOnlyDueDate() {
        let due = DateComponents(calendar: .current, year: 2026, month: 10, day: 19)

        let reminder = Reminder(from: ekReminder(rules: [], due: due))

        #expect(reminder.dueDate != nil)
        #expect(!reminder.dueDateHasTime)
    }

    @Test("no due date means no time")
    func noDueDate() {
        #expect(!Reminder(from: ekReminder(rules: [], due: nil)).dueDateHasTime)
    }

    @Test("a rule that can't be mapped reads as the unsupported marker and counts as having rules")
    func unmappedRule() {
        let rule = EKRecurrenceRule(
            recurrenceWith: .yearly, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: nil,
            monthsOfTheYear: nil, weeksOfTheYear: [20], daysOfTheYear: nil, setPositions: nil, end: nil)

        let reminder = Reminder(from: ekReminder(rules: [rule], due: DateComponents(calendar: .current, year: 2026, month: 10, day: 19)))

        #expect(reminder.recurrence == .unsupported(rrule: "FREQ=YEARLY;INTERVAL=1;BYWEEKNO=20"))
        #expect(reminder.hasRecurrenceRules)
    }

    @Test("more than one rule reads as the unsupported marker with both RRULEs")
    func severalRules() {
        let rules = [
            EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil),
            EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil),
        ]

        let reminder = Reminder(from: ekReminder(rules: rules, due: DateComponents(calendar: .current, year: 2026, month: 10, day: 19)))

        // An EKReminder doesn't promise to keep the order rules were set in, so compare as a set.
        guard case .unsupported(let rrule)? = reminder.recurrence else {
            Issue.record("expected the unsupported marker, got \(String(describing: reminder.recurrence))")
            return
        }
        #expect(Set(rrule.split(separator: "\n").map(String.init)) == ["FREQ=DAILY;INTERVAL=1", "FREQ=WEEKLY;INTERVAL=1"])
        #expect(reminder.hasRecurrenceRules)
    }

    @Test("JSON has recurrence as the rule object or null, plus dueDateHasTime")
    func jsonShape() throws {
        let plain = try encode(Reminder(from: ekReminder(rules: [], due: nil)))
        #expect(plain["recurrence"] is NSNull)
        #expect(plain["dueDateHasTime"] as? Bool == false)
        #expect(plain["hasRecurrenceRules"] as? Bool == false)

        let rule = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        let recurring = try encode(Reminder(from: ekReminder(rules: [rule], due: DateComponents(calendar: .current, year: 2026, month: 10, day: 19, hour: 9))))
        let object = try #require(recurring["recurrence"] as? [String: Any])
        #expect(object["frequency"] as? String == "daily")
        #expect(object["interval"] as? Int == 1)
        #expect(object["supported"] == nil)

        let weekNumbers = EKRecurrenceRule(
            recurrenceWith: .yearly, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: nil,
            monthsOfTheYear: nil, weeksOfTheYear: [20], daysOfTheYear: nil, setPositions: nil, end: nil)
        let custom = try encode(Reminder(from: ekReminder(rules: [weekNumbers], due: nil)))
        let marker = try #require(custom["recurrence"] as? [String: Any])
        #expect(marker["supported"] as? Bool == false)
        #expect(marker["rrule"] as? String == "FREQ=YEARLY;INTERVAL=1;BYWEEKNO=20")
        #expect(Set(marker.keys) == ["supported", "rrule"])
    }
}

// MARK: - Full rule vocabulary

private func ekRule(
    _ frequency: EKRecurrenceFrequency,
    interval: Int = 1,
    days: [EKRecurrenceDayOfWeek]? = nil,
    daysOfMonth: [Int]? = nil,
    months: [Int]? = nil,
    positions: [Int]? = nil,
    end: EKRecurrenceEnd? = nil
) -> EKRecurrenceRule {
    EKRecurrenceRule(
        recurrenceWith: frequency, interval: interval, daysOfTheWeek: days,
        daysOfTheMonth: daysOfMonth?.map { NSNumber(value: $0) },
        monthsOfTheYear: months?.map { NSNumber(value: $0) },
        weeksOfTheYear: nil, daysOfTheYear: nil,
        setPositions: positions?.map { NSNumber(value: $0) }, end: end)
}

private let thanksgiving = RecurrenceRule(
    frequency: .yearly, nthWeekday: NthWeekday(ordinal: 4, weekday: "thursday"), monthsOfYear: [11])

@Suite("Full vocabulary to EventKit")
struct FullVocabularyToEventKitTests {
    @Test("monthly days of the month")
    func daysOfMonth() throws {
        let ek = try RecurrenceRule(frequency: .monthly, interval: 2, daysOfMonth: [1, 15]).toEKRecurrenceRule()

        #expect(ek.frequency == .monthly)
        #expect(ek.interval == 2)
        #expect(ek.daysOfTheMonth?.map { $0.intValue } == [1, 15])
        #expect(ek.daysOfTheWeek == nil)
        #expect(ek.monthsOfTheYear == nil)
        #expect(ek.setPositions == nil)
    }

    @Test("repeated days of the month are written once")
    func dedupesDaysOfMonth() throws {
        let ek = try RecurrenceRule(frequency: .monthly, daysOfMonth: [15, 1, 15]).toEKRecurrenceRule()

        #expect(ek.daysOfTheMonth?.map { $0.intValue } == [15, 1])
    }

    @Test("monthly nth weekday is written in week-number form, like Reminders.app (BYDAY=1MO)")
    func monthlyNthWeekday() throws {
        let rule = RecurrenceRule(frequency: .monthly, nthWeekday: NthWeekday(ordinal: 1, weekday: "monday"))

        let ek = try rule.toEKRecurrenceRule()

        #expect(ek.daysOfTheWeek?.count == 1)
        #expect(ek.daysOfTheWeek?.first?.dayOfTheWeek == .monday)
        #expect(ek.daysOfTheWeek?.first?.weekNumber == 1)
        #expect(ek.setPositions == nil)
        #expect(ek.daysOfTheMonth == nil)
        #expect(ek.description.contains("BYDAY=1MO"))
    }

    @Test("the last weekday is week number -1")
    func lastWeekday() throws {
        let rule = RecurrenceRule(frequency: .monthly, nthWeekday: NthWeekday(ordinal: -1, weekday: "friday"))

        let ek = try rule.toEKRecurrenceRule()

        #expect(ek.daysOfTheWeek?.first?.dayOfTheWeek == .friday)
        #expect(ek.daysOfTheWeek?.first?.weekNumber == -1)
        #expect(ek.description.contains("BYDAY=-1FR"))
    }

    @Test("yearly months of the year")
    func monthsOfYear() throws {
        let ek = try RecurrenceRule(frequency: .yearly, monthsOfYear: [3, 6]).toEKRecurrenceRule()

        #expect(ek.frequency == .yearly)
        #expect(ek.monthsOfTheYear?.map { $0.intValue } == [3, 6])
        #expect(ek.daysOfTheWeek == nil)
    }

    @Test("Thanksgiving: yearly, November, fourth Thursday")
    func thanksgivingRule() throws {
        let ek = try thanksgiving.toEKRecurrenceRule()

        #expect(ek.frequency == .yearly)
        #expect(ek.monthsOfTheYear?.map { $0.intValue } == [11])
        #expect(ek.daysOfTheWeek?.first?.dayOfTheWeek == .thursday)
        #expect(ek.daysOfTheWeek?.first?.weekNumber == 4)
        #expect(ek.description.contains("BYMONTH=11"))
        #expect(ek.description.contains("BYDAY=4TH"))
    }

    @Test("occurrenceCount becomes an occurrence-count end")
    func occurrenceCount() throws {
        let ek = try RecurrenceRule(frequency: .daily, occurrenceCount: 3).toEKRecurrenceRule()

        #expect(ek.recurrenceEnd?.occurrenceCount == 3)
        #expect(ek.recurrenceEnd?.endDate == nil)
    }

    @Test("endDate becomes 23:59:59 on that day in the system time zone")
    func endDate() throws {
        let ek = try RecurrenceRule(frequency: .daily, endDate: "2026-12-31").toEKRecurrenceRule()

        let end = try #require(ek.recurrenceEnd?.endDate)
        #expect(ek.recurrenceEnd?.occurrenceCount == 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end)
        #expect(parts.year == 2026 && parts.month == 12 && parts.day == 31)
        #expect(parts.hour == 23 && parts.minute == 59 && parts.second == 59)
    }

    @Test("sends only the fields that apply")
    func sendsOnlyApplicableFields() throws {
        let ek = try RecurrenceRule(frequency: .monthly, daysOfMonth: [5]).toEKRecurrenceRule()

        #expect(ek.daysOfTheWeek == nil)
        #expect(ek.monthsOfTheYear == nil)
        #expect(ek.setPositions == nil)
        #expect(ek.recurrenceEnd == nil)
    }
}

@Suite("End of day")
struct EndOfDayTests {
    private func zone(_ id: String) -> TimeZone { TimeZone(identifier: id)! }

    @Test("converts to 23:59:59 and back to the same calendar date in several time zones")
    func roundTripsAcrossZones() throws {
        for id in ["UTC", "America/Los_Angeles", "Asia/Tokyo", "Pacific/Kiritimati", "Pacific/Pago_Pago"] {
            for day in ["2026-12-31", "2028-02-29", "2026-01-01", "2026-03-08", "2026-11-01"] {
                let end = try #require(RecurrenceRule.endOfDay(day, in: zone(id)), "\(day) \(id)")
                #expect(RecurrenceRule.calendarDate(of: end, in: zone(id)) == day)
            }
        }
    }

    @Test("the instant is the last second of the day")
    func lastSecond() throws {
        let tokyo = zone("Asia/Tokyo")
        let end = try #require(RecurrenceRule.endOfDay("2026-12-31", in: tokyo))

        // 2026-12-31T23:59:59+09:00 is 14:59:59Z
        #expect(end.timeIntervalSince1970 == 1_798_729_199)
        #expect(RecurrenceRule.calendarDate(of: end.addingTimeInterval(1), in: tokyo) == "2027-01-01")
    }

    @Test("rejects malformed and impossible dates")
    func rejectsBadDates() {
        for day in ["2026-02-30", "2026-13-01", "2026-00-10", "2027-02-29", "2026-04-31", "2026-1-5",
                    "12/31/2026", "2026-12-31T00:00:00Z", "tomorrow", "", "0000-01-01"] {
            #expect(RecurrenceRule.endOfDay(day, in: .current) == nil, "\(day)")
        }
    }
}

@Suite("Full vocabulary from EventKit")
struct FullVocabularyFromEventKitTests {
    @Test("monthly days of the month")
    func daysOfMonth() {
        let rule = ekRule(.monthly, interval: 2, daysOfMonth: [1, 15])

        #expect(RecurrenceRule.from(rule) == RecurrenceRule(frequency: .monthly, interval: 2, daysOfMonth: [1, 15]))
    }

    @Test("nth weekday in week-number form")
    func weekNumberForm() {
        let rule = ekRule(.monthly, days: [EKRecurrenceDayOfWeek(.monday, weekNumber: 1)])

        #expect(
            RecurrenceRule.from(rule)
                == RecurrenceRule(frequency: .monthly, nthWeekday: NthWeekday(ordinal: 1, weekday: "monday")))
    }

    @Test("nth weekday in position form: weekday Monday plus setPositions [1] is the first Monday")
    func positionForm() {
        let rule = ekRule(.monthly, days: [EKRecurrenceDayOfWeek(.monday)], positions: [1])

        #expect(
            RecurrenceRule.from(rule)
                == RecurrenceRule(frequency: .monthly, nthWeekday: NthWeekday(ordinal: 1, weekday: "monday")))
    }

    @Test("position -1 is the last weekday")
    func lastPosition() {
        let rule = ekRule(.monthly, days: [EKRecurrenceDayOfWeek(.friday)], positions: [-1])

        #expect(
            RecurrenceRule.from(rule)
                == RecurrenceRule(frequency: .monthly, nthWeekday: NthWeekday(ordinal: -1, weekday: "friday")))
    }

    @Test("both encodings of Thanksgiving read the same")
    func thanksgivingBothForms() {
        let weekNumber = ekRule(.yearly, days: [EKRecurrenceDayOfWeek(.thursday, weekNumber: 4)], months: [11])
        let position = ekRule(.yearly, days: [EKRecurrenceDayOfWeek(.thursday)], months: [11], positions: [4])

        #expect(RecurrenceRule.from(weekNumber) == thanksgiving)
        #expect(RecurrenceRule.from(position) == thanksgiving)
    }

    @Test("yearly months of the year")
    func monthsOfYear() {
        #expect(
            RecurrenceRule.from(ekRule(.yearly, months: [3, 6]))
                == RecurrenceRule(frequency: .yearly, monthsOfYear: [3, 6]))
    }

    @Test("occurrenceCount is read as-is")
    func occurrenceCount() {
        let rule = ekRule(.daily, end: EKRecurrenceEnd(occurrenceCount: 7))

        #expect(RecurrenceRule.from(rule) == RecurrenceRule(frequency: .daily, occurrenceCount: 7))
    }

    @Test("an end date reads back as the local calendar date")
    func endDate() throws {
        let end = try #require(RecurrenceRule.endOfDay("2026-12-31", in: .current))

        #expect(
            RecurrenceRule.from(ekRule(.weekly, end: EKRecurrenceEnd(end: end)))
                == RecurrenceRule(frequency: .weekly, endDate: "2026-12-31"))
    }

    @Test("round-trips the whole vocabulary")
    func roundTrips() throws {
        let rules = [
            RecurrenceRule(frequency: .monthly),
            RecurrenceRule(frequency: .monthly, interval: 2, daysOfMonth: [1, 15, 31]),
            RecurrenceRule(frequency: .monthly, nthWeekday: NthWeekday(ordinal: 1, weekday: "monday")),
            RecurrenceRule(frequency: .monthly, nthWeekday: NthWeekday(ordinal: -1, weekday: "friday"), endDate: "2027-06-30"),
            RecurrenceRule(frequency: .monthly, nthWeekday: NthWeekday(ordinal: 5, weekday: "sunday"), occurrenceCount: 4),
            RecurrenceRule(frequency: .yearly),
            RecurrenceRule(frequency: .yearly, interval: 2, monthsOfYear: [3, 6]),
            thanksgiving,
            RecurrenceRule(frequency: .daily, endDate: "2026-12-31"),
            RecurrenceRule(frequency: .weekly, daysOfWeek: ["monday"], occurrenceCount: 3),
        ]
        for rule in rules {
            #expect(RecurrenceRule.from(try rule.toEKRecurrenceRule()) == rule, "\(rule)")
        }
    }

    @Test("patterns that don't map exactly are nil, never approximated")
    func unmapped() {
        let monday = EKRecurrenceDayOfWeek(.monday)
        let tuesday = EKRecurrenceDayOfWeek(.tuesday)
        let rules: [EKRecurrenceRule] = [
            // every Monday of the month: weekday without a position
            ekRule(.monthly, days: [monday]),
            // weekday set with a position (first Monday or Tuesday)
            ekRule(.monthly, days: [monday, tuesday], positions: [1]),
            // weekday set (last weekday-ish) with several positions
            ekRule(.monthly, days: [monday], positions: [1, 3]),
            // position out of range
            ekRule(.monthly, days: [monday], positions: [6]),
            ekRule(.monthly, days: [monday], positions: [-2]),
            // several ordinals
            ekRule(.monthly, days: [EKRecurrenceDayOfWeek(.monday, weekNumber: 1), EKRecurrenceDayOfWeek(.monday, weekNumber: 3)]),
            // ordinal out of range
            ekRule(.monthly, days: [EKRecurrenceDayOfWeek(.monday, weekNumber: 6)]),
            // week number and a position together
            ekRule(.monthly, days: [EKRecurrenceDayOfWeek(.monday, weekNumber: 1)], positions: [1]),
            // days of month together with a weekday
            ekRule(.monthly, days: [EKRecurrenceDayOfWeek(.monday, weekNumber: 1)], daysOfMonth: [1]),
            // negative days of month
            ekRule(.monthly, daysOfMonth: [-1]),
            ekRule(.monthly, daysOfMonth: [1, -1]),
            // months on a monthly rule, days of month on a yearly one
            ekRule(.monthly, months: [3]),
            ekRule(.yearly, daysOfMonth: [1]),
            // yearly nth weekday without months can't be written back, so it isn't reported
            ekRule(.yearly, days: [EKRecurrenceDayOfWeek(.thursday, weekNumber: 4)]),
            // position on a rule without a weekday
            ekRule(.monthly, positions: [1]),
            // weekly with a position
            ekRule(.weekly, days: [monday], positions: [1]),
        ]
        for (index, rule) in rules.enumerated() {
            #expect(RecurrenceRule.from(rule) == nil, "rule \(index): \(rule)")
        }
    }
}

@Suite("Full vocabulary validation")
struct FullVocabularyValidationTests {
    private func message(_ rule: RecurrenceRule) -> String? { errorMessage { try rule.validate() } }
    private let monday = NthWeekday(ordinal: 1, weekday: "monday")

    @Test("accepts every valid shape")
    func acceptsValid() throws {
        try RecurrenceRule(frequency: .monthly, daysOfMonth: [1, 31]).validate()
        try RecurrenceRule(frequency: .monthly, nthWeekday: monday).validate()
        try RecurrenceRule(frequency: .monthly, nthWeekday: NthWeekday(ordinal: -1, weekday: "friday")).validate()
        try RecurrenceRule(frequency: .yearly, monthsOfYear: [1, 12]).validate()
        try thanksgiving.validate()
        try RecurrenceRule(frequency: .daily, endDate: "2028-02-29").validate()
        try RecurrenceRule(frequency: .daily, occurrenceCount: 1).validate()
    }

    @Test("rejects fields that don't apply to the frequency")
    func rejectsMismatches() {
        for frequency in [RecurrenceFrequency.daily, .weekly, .yearly] {
            #expect(message(RecurrenceRule(frequency: frequency, daysOfMonth: [1])) == "daysOfMonth only applies to monthly rules")
        }
        for frequency in [RecurrenceFrequency.daily, .weekly, .monthly] {
            #expect(message(RecurrenceRule(frequency: frequency, monthsOfYear: [3])) == "monthsOfYear only applies to yearly rules")
        }
        for frequency in [RecurrenceFrequency.daily, .weekly] {
            #expect(
                message(RecurrenceRule(frequency: frequency, nthWeekday: monday))
                    == "nthWeekday only applies to monthly and yearly rules")
        }
    }

    @Test("rejects daysOfMonth together with nthWeekday")
    func rejectsBoth() {
        #expect(
            message(RecurrenceRule(frequency: .monthly, daysOfMonth: [1], nthWeekday: monday))
                == "Use either daysOfMonth or nthWeekday, not both")
    }

    @Test("rejects a yearly nthWeekday without monthsOfYear")
    func yearlyNthNeedsMonths() {
        #expect(
            message(RecurrenceRule(frequency: .yearly, nthWeekday: NthWeekday(ordinal: 4, weekday: "thursday")))
                == "A yearly nthWeekday needs monthsOfYear (e.g. the fourth Thursday of November)")
    }

    @Test("rejects endDate together with occurrenceCount")
    func rejectsEndAndCount() {
        #expect(
            message(RecurrenceRule(frequency: .daily, endDate: "2026-12-31", occurrenceCount: 3))
                == "Use either endDate or occurrenceCount, not both")
    }

    @Test("rejects days of month outside 1-31")
    func rejectsDayRange() {
        for day in [0, 32, -1, 100, Int.min, Int.max] {
            #expect(
                message(RecurrenceRule(frequency: .monthly, daysOfMonth: [1, day]))
                    == "daysOfMonth must be whole numbers from 1 to 31")
        }
    }

    @Test("rejects months outside 1-12")
    func rejectsMonthRange() {
        for month in [0, 13, -1, Int.max] {
            #expect(
                message(RecurrenceRule(frequency: .yearly, monthsOfYear: [month]))
                    == "monthsOfYear must be whole numbers from 1 to 12")
        }
    }

    @Test("rejects ordinals other than 1-5 and -1")
    func rejectsOrdinal() {
        for ordinal in [0, 6, -2, 53, -53, Int.max, Int.min] {
            #expect(
                message(RecurrenceRule(frequency: .monthly, nthWeekday: NthWeekday(ordinal: ordinal, weekday: "monday")))
                    == "nthWeekday.ordinal must be 1, 2, 3, 4, 5 or -1 (last)")
        }
    }

    @Test("rejects an unknown nthWeekday weekday")
    func rejectsNthWeekdayName() {
        for name in ["mon", "Monday", "someday", ""] {
            #expect(
                message(RecurrenceRule(frequency: .monthly, nthWeekday: NthWeekday(ordinal: 1, weekday: name)))
                    == "nthWeekday.weekday must use a full lowercase weekday name: sunday, monday, tuesday, wednesday, thursday, friday, saturday")
        }
    }

    @Test("rejects empty arrays")
    func rejectsEmptyArrays() {
        #expect(
            message(RecurrenceRule(frequency: .monthly, daysOfMonth: []))
                == "daysOfMonth can't be empty: omit it to repeat on the due date's day")
        #expect(
            message(RecurrenceRule(frequency: .yearly, monthsOfYear: []))
                == "monthsOfYear can't be empty: omit it to repeat in the due date's month")
    }

    @Test("rejects an occurrenceCount below 1, which would raise an uncatchable exception in EventKit")
    func rejectsCount() {
        for count in [0, -1, Int.min] {
            #expect(
                message(RecurrenceRule(frequency: .daily, occurrenceCount: count))
                    == "occurrenceCount must be a whole number, 1 or greater")
            #expect(errorMessage { _ = try RecurrenceRule(frequency: .daily, occurrenceCount: count).toEKRecurrenceRule() } != nil)
        }
    }

    @Test("rejects malformed and impossible end dates")
    func rejectsEndDate() {
        for day in ["2026-02-30", "2026-13-01", "2027-02-29", "2026-12-31T00:00:00Z", "12/31/2026", "tomorrow", ""] {
            #expect(
                message(RecurrenceRule(frequency: .daily, endDate: day))
                    == "endDate must be a real calendar date in YYYY-MM-DD format (e.g. 2026-12-31)")
        }
    }

    @Test("toEKRecurrenceRule refuses every one of these before EventKit sees them")
    func conversionValidatesFirst() {
        let bad = [
            RecurrenceRule(frequency: .monthly, daysOfMonth: [32]),
            RecurrenceRule(frequency: .yearly, monthsOfYear: [13]),
            RecurrenceRule(frequency: .monthly, nthWeekday: NthWeekday(ordinal: 6, weekday: "monday")),
            RecurrenceRule(frequency: .daily, endDate: "2026-02-30"),
            RecurrenceRule(frequency: .daily, endDate: "2026-12-31", occurrenceCount: 2),
        ]
        for rule in bad {
            #expect(errorMessage { _ = try rule.toEKRecurrenceRule() } != nil, "\(rule)")
        }
    }
}

@Suite("Full vocabulary JSON")
struct FullVocabularyJSONTests {
    private func decode(_ json: String) throws -> RecurrenceRule {
        try JSONDecoder().decode(RecurrenceRule.self, from: Data(json.utf8))
    }

    @Test("decodes every new field")
    func decodesNewFields() throws {
        let rule = try decode(
            #"{"frequency":"yearly","monthsOfYear":[11],"nthWeekday":{"ordinal":4,"weekday":"thursday"},"endDate":"2030-11-28"}"#)

        #expect(
            rule == RecurrenceRule(
                frequency: .yearly, nthWeekday: NthWeekday(ordinal: 4, weekday: "thursday"),
                monthsOfYear: [11], endDate: "2030-11-28"))
        #expect(try decode(#"{"frequency":"monthly","daysOfMonth":[1,15],"occurrenceCount":3}"#)
            == RecurrenceRule(frequency: .monthly, daysOfMonth: [1, 15], occurrenceCount: 3))
    }

    @Test("an out-of-range value decodes, then fails validation with a specific message")
    func outOfRangeFailsValidation() throws {
        let rule = try decode(#"{"frequency":"daily","occurrenceCount":0}"#)

        #expect(errorMessage { try rule.validate() } == "occurrenceCount must be a whole number, 1 or greater")
    }

    @Test("encodes only the fields that apply")
    func encodesCompactly() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let json = try encoder.encode(thanksgiving)

        #expect(
            String(decoding: json, as: UTF8.self)
                == #"{"frequency":"yearly","interval":1,"monthsOfYear":[11],"nthWeekday":{"ordinal":4,"weekday":"thursday"}}"#)
    }
}

// MARK: - Unsupported recurrence rules

private func yearlyRule(weeks: [Int]? = nil, daysOfYear: [Int]? = nil) -> EKRecurrenceRule {
    EKRecurrenceRule(
        recurrenceWith: .yearly, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: nil,
        monthsOfTheYear: nil, weeksOfTheYear: weeks?.map { NSNumber(value: $0) },
        daysOfTheYear: daysOfYear?.map { NSNumber(value: $0) }, setPositions: nil, end: nil)
}

@Suite("RRULE extraction")
struct RRuleExtractionTests {
    @Test("takes the part after RRULE from EventKit's description")
    func extracts() {
        let description = "EKRecurrenceRule <0x600000c1c2a0> RRULE FREQ=MONTHLY;INTERVAL=1;BYDAY=MO"

        #expect(ReminderRecurrence.rrule(fromDescription: description) == "FREQ=MONTHLY;INTERVAL=1;BYDAY=MO")
    }

    @Test("works on a real rule's description")
    func realDescription() {
        let rule = ekRule(.weekly, interval: 2, end: EKRecurrenceEnd(occurrenceCount: 3))

        #expect(ReminderRecurrence.rrule(of: rule) == "FREQ=WEEKLY;INTERVAL=2;COUNT=3")
    }

    @Test("falls back to the whole description when there is no RRULE marker")
    func fallsBack() {
        #expect(ReminderRecurrence.rrule(fromDescription: "something else entirely") == "something else entirely")
        #expect(ReminderRecurrence.rrule(fromDescription: "") == "")
        #expect(ReminderRecurrence.rrule(fromDescription: "EKRecurrenceRule <0x1> RRULE ") == "EKRecurrenceRule <0x1> RRULE ")
    }
}

@Suite("Unsupported recurrence rules")
struct UnsupportedRecurrenceTests {
    private let monday = EKRecurrenceDayOfWeek(.monday)
    private let tuesday = EKRecurrenceDayOfWeek(.tuesday)

    private func unsupported(_ rule: EKRecurrenceRule) -> String? {
        if case .unsupported(let rrule)? = ReminderRecurrence.from(rules: [rule]) { return rrule }
        return nil
    }

    @Test("weeks of the year")
    func weeksOfTheYear() {
        #expect(unsupported(yearlyRule(weeks: [20])) == "FREQ=YEARLY;INTERVAL=1;BYWEEKNO=20")
    }

    @Test("days of the year")
    func daysOfTheYear() {
        #expect(unsupported(yearlyRule(daysOfYear: [100])) == "FREQ=YEARLY;INTERVAL=1;BYYEARDAY=100")
    }

    @Test("a weekday set with a position, like the last weekday")
    func weekdaySetWithPosition() {
        let rule = ekRule(.monthly, days: [monday, tuesday], positions: [-1])

        #expect(unsupported(rule) == "FREQ=MONTHLY;INTERVAL=1;BYDAY=MO,TU;BYSETPOS=-1")
    }

    @Test("a daily rule with weekdays")
    func dailyWithWeekdays() {
        #expect(unsupported(ekRule(.daily, days: [monday])) == "FREQ=DAILY;INTERVAL=1;BYDAY=MO")
    }

    @Test("multiple ordinals")
    func multipleOrdinals() {
        let rule = ekRule(
            .monthly,
            days: [EKRecurrenceDayOfWeek(.monday, weekNumber: 1), EKRecurrenceDayOfWeek(.monday, weekNumber: 3)])

        #expect(unsupported(rule) == "FREQ=MONTHLY;INTERVAL=1;BYDAY=1MO,3MO")
    }

    @Test("negative days of the month")
    func negativeDaysOfMonth() {
        #expect(unsupported(ekRule(.monthly, daysOfMonth: [-1])) == "FREQ=MONTHLY;INTERVAL=1;BYMONTHDAY=-1")
    }

    @Test("the end condition stays in the RRULE")
    func keepsEnd() {
        let rule = ekRule(.daily, days: [monday], end: EKRecurrenceEnd(occurrenceCount: 3))

        #expect(unsupported(rule) == "FREQ=DAILY;INTERVAL=1;COUNT=3;BYDAY=MO")
    }

    @Test("several rules are joined with a newline, in order")
    func severalRules() {
        let rules = [
            ekRule(.daily),
            ekRule(.weekly, days: [monday]),
            ekRule(.monthly, daysOfMonth: [1]),
        ]

        #expect(
            ReminderRecurrence.from(rules: rules)
                == .unsupported(
                    rrule: "FREQ=DAILY;INTERVAL=1\nFREQ=WEEKLY;INTERVAL=1;BYDAY=MO\nFREQ=MONTHLY;INTERVAL=1;BYMONTHDAY=1"))
    }

    @Test("two rules are unsupported even when each alone would be supported")
    func twoSupportedRules() {
        let rules = [ekRule(.daily), ekRule(.daily)]

        #expect(ReminderRecurrence.from(rules: rules) == .unsupported(rrule: "FREQ=DAILY;INTERVAL=1\nFREQ=DAILY;INTERVAL=1"))
    }

    @Test("one supported rule maps to the supported case")
    func supportedRule() {
        #expect(
            ReminderRecurrence.from(rules: [ekRule(.weekly, interval: 2, days: [monday])])
                == .supported(RecurrenceRule(frequency: .weekly, interval: 2, daysOfWeek: ["monday"])))
    }

    @Test("no rules map to nil")
    func noRules() {
        #expect(ReminderRecurrence.from(rules: []) == nil)
        #expect(ReminderRecurrence.from(rules: nil) == nil)
    }
}

@Suite("ReminderRecurrence coding")
struct ReminderRecurrenceCodingTests {
    private func json(_ value: ReminderRecurrence) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    @Test("a supported rule encodes as the plain rule object, without a supported key")
    func encodesSupported() throws {
        let value = ReminderRecurrence.supported(RecurrenceRule(frequency: .weekly, interval: 2, daysOfWeek: ["monday"]))

        #expect(try json(value) == #"{"daysOfWeek":["monday"],"frequency":"weekly","interval":2}"#)
    }

    @Test("the marker encodes as supported:false plus the RRULE")
    func encodesMarker() throws {
        let value = ReminderRecurrence.unsupported(rrule: "FREQ=MONTHLY;INTERVAL=1;BYDAY=MO")

        #expect(try json(value) == #"{"rrule":"FREQ=MONTHLY;INTERVAL=1;BYDAY=MO","supported":false}"#)
    }

    @Test("both shapes decode back")
    func roundTrips() throws {
        let values: [ReminderRecurrence] = [
            .supported(RecurrenceRule(frequency: .daily, occurrenceCount: 3)),
            .unsupported(rrule: "FREQ=YEARLY;INTERVAL=1;BYWEEKNO=20"),
        ]
        for value in values {
            let decoded = try JSONDecoder().decode(ReminderRecurrence.self, from: Data(try json(value).utf8))
            #expect(decoded == value)
        }
    }
}
