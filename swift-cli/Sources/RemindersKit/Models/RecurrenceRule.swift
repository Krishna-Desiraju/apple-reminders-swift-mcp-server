import Foundation
import EventKit

/// Recurrence frequency for recurring reminders
public enum RecurrenceFrequency: String, Codable {
    case daily
    case weekly
    case monthly
    case yearly
}

/// A weekday, spelled as on the wire: full lowercase English names.
/// EventKit's raw values run 1 = Sunday through 7 = Saturday.
public enum Weekday: String, Codable, CaseIterable {
    case sunday
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    /// The weekday for a wire name, or nil if it isn't a full lowercase weekday name
    public init?(name: String) {
        self.init(rawValue: name)
    }

    public init?(ekWeekday: EKWeekday) {
        switch ekWeekday {
        case .sunday: self = .sunday
        case .monday: self = .monday
        case .tuesday: self = .tuesday
        case .wednesday: self = .wednesday
        case .thursday: self = .thursday
        case .friday: self = .friday
        case .saturday: self = .saturday
        @unknown default: return nil
        }
    }

    public var ekWeekday: EKWeekday {
        switch self {
        case .sunday: return .sunday
        case .monday: return .monday
        case .tuesday: return .tuesday
        case .wednesday: return .wednesday
        case .thursday: return .thursday
        case .friday: return .friday
        case .saturday: return .saturday
        }
    }
}

/// "The Nth weekday" of a month: the first Monday, the last Friday.
/// Both fields are plain values so that out-of-range input decodes and `RecurrenceRule.validate()`
/// can reject it with a message that names the field.
public struct NthWeekday: Codable, Equatable {
    /// 1 = first through 5 = fifth, or -1 for the last
    public let ordinal: Int
    /// Full lowercase weekday name
    public let weekday: String

    public init(ordinal: Int, weekday: String) {
        self.ordinal = ordinal
        self.weekday = weekday
    }
}

/// The recurrence rule of a recurring reminder, in the shape used on the wire for both input
/// (create) and output (reads).
///
/// Always call `validate()` (or `toEKRecurrenceRule()`, which does) before handing anything to
/// EventKit: a bad interval, occurrence count or weekday makes EventKit raise an Objective-C
/// exception, which Swift can't catch, and that crashes the CLI.
public struct RecurrenceRule: Codable, Equatable {
    public let frequency: RecurrenceFrequency
    public let interval: Int // e.g., every 2 weeks; at least 1
    /// Weekly only. Full lowercase weekday names, kept as strings so an unknown name survives
    /// decoding and `validate()` can reject it with a message that names it.
    public let daysOfWeek: [String]?
    /// Monthly only. Days of the month, 1-31.
    public let daysOfMonth: [Int]?
    /// Monthly or yearly. A yearly one also needs `monthsOfYear`.
    public let nthWeekday: NthWeekday?
    /// Yearly only. Months, 1 = January through 12 = December.
    public let monthsOfYear: [Int]?
    /// "YYYY-MM-DD", inclusive: the last day an occurrence can fall on.
    public let endDate: String?
    /// Occurrences remaining, including the current one.
    public let occurrenceCount: Int?

    public init(
        frequency: RecurrenceFrequency,
        interval: Int = 1,
        daysOfWeek: [String]? = nil,
        daysOfMonth: [Int]? = nil,
        nthWeekday: NthWeekday? = nil,
        monthsOfYear: [Int]? = nil,
        endDate: String? = nil,
        occurrenceCount: Int? = nil
    ) {
        self.frequency = frequency
        self.interval = interval
        self.daysOfWeek = daysOfWeek
        self.daysOfMonth = daysOfMonth
        self.nthWeekday = nthWeekday
        self.monthsOfYear = monthsOfYear
        self.endDate = endDate
        self.occurrenceCount = occurrenceCount
    }

    private enum CodingKeys: String, CodingKey {
        case frequency, interval, daysOfWeek, daysOfMonth, nthWeekday, monthsOfYear, endDate, occurrenceCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.frequency = try container.decode(RecurrenceFrequency.self, forKey: .frequency)
        self.interval = try container.decodeIfPresent(Int.self, forKey: .interval) ?? 1
        self.daysOfWeek = try container.decodeIfPresent([String].self, forKey: .daysOfWeek)
        self.daysOfMonth = try container.decodeIfPresent([Int].self, forKey: .daysOfMonth)
        self.nthWeekday = try container.decodeIfPresent(NthWeekday.self, forKey: .nthWeekday)
        self.monthsOfYear = try container.decodeIfPresent([Int].self, forKey: .monthsOfYear)
        self.endDate = try container.decodeIfPresent(String.self, forKey: .endDate)
        self.occurrenceCount = try container.decodeIfPresent(Int.self, forKey: .occurrenceCount)
    }

    // MARK: - Validation

    public static let needsDueDateMessage =
        "A recurring reminder needs a due date: pass dueDate as the first occurrence."

    /// Check the rule, throwing `ReminderError.invalidInput` with an agent-readable message.
    /// Keep the messages in step with the Zod schema in src/validation/reminder-schemas.ts.
    public func validate() throws {
        func reject(_ message: String) -> ReminderError { ReminderError.invalidInput(message) }

        if interval < 1 {
            throw reject("interval must be a whole number, 1 or greater")
        }

        if let daysOfWeek = daysOfWeek {
            if frequency != .weekly {
                throw reject("daysOfWeek only applies to weekly rules")
            }
            if daysOfWeek.isEmpty {
                throw reject("daysOfWeek can't be empty: omit it to repeat on the due date's weekday")
            }
            if daysOfWeek.contains(where: { Weekday(name: $0) == nil }) {
                throw reject("daysOfWeek must use full lowercase weekday names: \(Self.weekdayNames)")
            }
        }

        if let daysOfMonth = daysOfMonth {
            if frequency != .monthly {
                throw reject("daysOfMonth only applies to monthly rules")
            }
            if daysOfMonth.isEmpty {
                throw reject("daysOfMonth can't be empty: omit it to repeat on the due date's day")
            }
            if daysOfMonth.contains(where: { !(1...31).contains($0) }) {
                throw reject("daysOfMonth must be whole numbers from 1 to 31")
            }
        }

        if let monthsOfYear = monthsOfYear {
            if frequency != .yearly {
                throw reject("monthsOfYear only applies to yearly rules")
            }
            if monthsOfYear.isEmpty {
                throw reject("monthsOfYear can't be empty: omit it to repeat in the due date's month")
            }
            if monthsOfYear.contains(where: { !(1...12).contains($0) }) {
                throw reject("monthsOfYear must be whole numbers from 1 to 12")
            }
        }

        if let nthWeekday = nthWeekday {
            if frequency != .monthly && frequency != .yearly {
                throw reject("nthWeekday only applies to monthly and yearly rules")
            }
            if !Self.allowedOrdinals.contains(nthWeekday.ordinal) {
                throw reject("nthWeekday.ordinal must be 1, 2, 3, 4, 5 or -1 (last)")
            }
            if Weekday(name: nthWeekday.weekday) == nil {
                throw reject(
                    "nthWeekday.weekday must use a full lowercase weekday name: \(Self.weekdayNames)"
                )
            }
            if daysOfMonth != nil {
                throw reject("Use either daysOfMonth or nthWeekday, not both")
            }
            if frequency == .yearly && monthsOfYear == nil {
                throw reject(
                    "A yearly nthWeekday needs monthsOfYear (e.g. the fourth Thursday of November)"
                )
            }
        }

        if let endDate = endDate {
            if Self.endOfDay(endDate) == nil {
                throw reject(
                    "endDate must be a real calendar date in YYYY-MM-DD format (e.g. 2026-12-31)"
                )
            }
        }
        if let occurrenceCount = occurrenceCount {
            // EKRecurrenceEnd(occurrenceCount: 0) raises an uncatchable exception.
            if occurrenceCount < 1 {
                throw reject("occurrenceCount must be a whole number, 1 or greater")
            }
        }
        if endDate != nil && occurrenceCount != nil {
            throw reject("Use either endDate or occurrenceCount, not both")
        }
    }

    /// Check the rule, then check that the reminder it goes on has a due date.
    /// - Parameter dueDate: The reminder's due date input, if any
    public func validate(dueDate: String?) throws {
        try validate()
        if dueDate == nil {
            throw ReminderError.invalidInput(Self.needsDueDateMessage)
        }
    }

    private static let allowedOrdinals = [1, 2, 3, 4, 5, -1]

    private static var weekdayNames: String {
        Weekday.allCases.map { $0.rawValue }.joined(separator: ", ")
    }

    // MARK: - End date

    /// The calendar used for end dates: Gregorian, so "2026-12-31" means the same thing whatever
    /// calendar the user's system uses, in the given time zone.
    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// 23:59:59 on a "YYYY-MM-DD" day in the given time zone (the system's by default).
    /// Returns nil unless the string is a real calendar date written exactly that way.
    public static func endOfDay(_ day: String, in timeZone: TimeZone = .current) -> Date? {
        let characters = Array(day.utf8)
        guard characters.count == 10, characters[4] == UInt8(ascii: "-"), characters[7] == UInt8(ascii: "-")
        else { return nil }
        let digits = characters.enumerated().filter { $0.offset != 4 && $0.offset != 7 }.map { $0.element }
        guard digits.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }) else { return nil }

        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] >= 1 else { return nil }

        let calendar = calendar(in: timeZone)
        let components = DateComponents(
            year: parts[0], month: parts[1], day: parts[2], hour: 23, minute: 59, second: 59)
        guard let date = calendar.date(from: components) else { return nil }

        // date(from:) rolls impossible dates over (Feb 30 becomes Mar 2), so check it came back unchanged.
        let back = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard back.year == parts[0], back.month == parts[1], back.day == parts[2],
              back.hour == 23, back.minute == 59, back.second == 59
        else { return nil }
        return date
    }

    /// The "YYYY-MM-DD" calendar date of an instant in the given time zone (the system's by default).
    public static func calendarDate(of date: Date, in timeZone: TimeZone = .current) -> String {
        let parts = calendar(in: timeZone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: - EventKit

    /// Convert to EKRecurrenceRule, validating first
    public func toEKRecurrenceRule() throws -> EKRecurrenceRule {
        try validate()

        let ekFrequency: EKRecurrenceFrequency
        switch frequency {
        case .daily:
            ekFrequency = .daily
        case .weekly:
            ekFrequency = .weekly
        case .monthly:
            ekFrequency = .monthly
        case .yearly:
            ekFrequency = .yearly
        }

        var ekDaysOfWeek: [EKRecurrenceDayOfWeek]?
        if let daysOfWeek = daysOfWeek {
            ekDaysOfWeek = Self.unique(daysOfWeek.compactMap { Weekday(name: $0) })
                .map { EKRecurrenceDayOfWeek($0.ekWeekday) }
        } else if let nthWeekday = nthWeekday, let weekday = Weekday(name: nthWeekday.weekday) {
            // The week-number form (BYDAY=1MO) is what Reminders.app writes itself.
            ekDaysOfWeek = [EKRecurrenceDayOfWeek(weekday.ekWeekday, weekNumber: nthWeekday.ordinal)]
        }

        var ekEnd: EKRecurrenceEnd?
        if let endDate = endDate, let end = Self.endOfDay(endDate) {
            ekEnd = EKRecurrenceEnd(end: end)
        } else if let occurrenceCount = occurrenceCount {
            ekEnd = EKRecurrenceEnd(occurrenceCount: occurrenceCount)
        }

        return EKRecurrenceRule(
            recurrenceWith: ekFrequency,
            interval: interval,
            daysOfTheWeek: ekDaysOfWeek,
            daysOfTheMonth: daysOfMonth.map { Self.unique($0).map { NSNumber(value: $0) } },
            monthsOfTheYear: monthsOfYear.map { Self.unique($0).map { NSNumber(value: $0) } },
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: ekEnd
        )
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }

    /// Create from EKRecurrenceRule.
    ///
    /// Returns nil for a rule this model can't express exactly. Never approximates: a rule that
    /// reads back as something it isn't would be silently rewritten by a later update.
    public static func from(_ ekRule: EKRecurrenceRule) -> RecurrenceRule? {
        guard (ekRule.weeksOfTheYear ?? []).isEmpty, (ekRule.daysOfTheYear ?? []).isEmpty else {
            return nil
        }

        let frequency: RecurrenceFrequency
        switch ekRule.frequency {
        case .daily:
            frequency = .daily
        case .weekly:
            frequency = .weekly
        case .monthly:
            frequency = .monthly
        case .yearly:
            frequency = .yearly
        @unknown default:
            return nil
        }

        let ekDays = ekRule.daysOfTheWeek ?? []
        let positions = (ekRule.setPositions ?? []).map { $0.intValue }
        let ekDaysOfMonth = (ekRule.daysOfTheMonth ?? []).map { $0.intValue }
        let ekMonths = (ekRule.monthsOfTheYear ?? []).map { $0.intValue }

        var daysOfWeek: [String]?
        var nthWeekday: NthWeekday?
        switch frequency {
        case .daily:
            guard ekDays.isEmpty, positions.isEmpty else { return nil }
        case .weekly:
            guard positions.isEmpty else { return nil }
            if !ekDays.isEmpty {
                var names: [String] = []
                for day in ekDays {
                    // An ordinal weekday ("first Monday") is a different pattern.
                    guard day.weekNumber == 0, let weekday = Weekday(ekWeekday: day.dayOfTheWeek) else {
                        return nil
                    }
                    names.append(weekday.rawValue)
                }
                daysOfWeek = names
            }
        case .monthly, .yearly:
            if !ekDays.isEmpty {
                nthWeekday = normalizedNthWeekday(from: ekDays, positions: positions)
                guard nthWeekday != nil else { return nil }
            } else if !positions.isEmpty {
                return nil
            }
        }

        // Only a monthly rule has days of the month, and only positive ones map.
        if !ekDaysOfMonth.isEmpty {
            guard frequency == .monthly, nthWeekday == nil,
                  ekDaysOfMonth.allSatisfy({ (1...31).contains($0) })
            else { return nil }
        }
        // Only a yearly rule has months.
        if !ekMonths.isEmpty {
            guard frequency == .yearly, ekMonths.allSatisfy({ (1...12).contains($0) }) else { return nil }
        }

        var endDate: String?
        var occurrenceCount: Int?
        if let end = ekRule.recurrenceEnd {
            if end.occurrenceCount > 0 {
                occurrenceCount = end.occurrenceCount
            } else if let date = end.endDate {
                endDate = calendarDate(of: date)
            } else {
                return nil
            }
        }

        let rule = RecurrenceRule(
            frequency: frequency,
            interval: ekRule.interval,
            daysOfWeek: daysOfWeek,
            daysOfMonth: ekDaysOfMonth.isEmpty ? nil : ekDaysOfMonth,
            nthWeekday: nthWeekday,
            monthsOfYear: ekMonths.isEmpty ? nil : ekMonths,
            endDate: endDate,
            occurrenceCount: occurrenceCount
        )
        // A rule this model couldn't write back isn't one it can report.
        guard (try? rule.validate()) != nil else { return nil }
        return rule
    }

    /// Normalise both encodings of "the Nth weekday" into one value, or nil if the weekdays and
    /// positions aren't exactly one of them:
    /// - a single weekday with a non-zero week number (what Reminders.app writes);
    /// - a single plain weekday with a single position of 1...5 or -1.
    private static func normalizedNthWeekday(from days: [EKRecurrenceDayOfWeek], positions: [Int]) -> NthWeekday? {
        guard days.count == 1, let day = days.first,
              let weekday = Weekday(ekWeekday: day.dayOfTheWeek)
        else { return nil }

        let ordinal: Int
        if day.weekNumber != 0 {
            guard positions.isEmpty else { return nil }
            ordinal = day.weekNumber
        } else {
            guard positions.count == 1, let position = positions.first else { return nil }
            ordinal = position
        }
        guard allowedOrdinals.contains(ordinal) else { return nil }
        return NthWeekday(ordinal: ordinal, weekday: weekday.rawValue)
    }
}
