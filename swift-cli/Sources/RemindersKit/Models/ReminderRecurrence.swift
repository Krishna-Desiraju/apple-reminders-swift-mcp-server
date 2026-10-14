import Foundation
import EventKit

/// What a read reports about a reminder's recurrence: a rule this server can express exactly,
/// or a marker for one it can't.
///
/// Wire format:
/// - supported: the plain `RecurrenceRule` object, with no `supported` key;
/// - unsupported: `{ "supported": false, "rrule": "<RRULE>" }`.
/// A reminder with no rules has no `ReminderRecurrence` at all (`recurrence: null`).
public enum ReminderRecurrence: Codable, Equatable {
    case supported(RecurrenceRule)
    /// `rrule` is EventKit's own RRULE text. With several rules, one RRULE per line.
    case unsupported(rrule: String)

    private enum MarkerKeys: String, CodingKey {
        case supported, rrule
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: MarkerKeys.self)
        if try container.decodeIfPresent(Bool.self, forKey: .supported) == false {
            self = .unsupported(rrule: try container.decode(String.self, forKey: .rrule))
        } else {
            self = .supported(try RecurrenceRule(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .supported(let rule):
            try rule.encode(to: encoder)
        case .unsupported(let rrule):
            var container = encoder.container(keyedBy: MarkerKeys.self)
            try container.encode(false, forKey: .supported)
            try container.encode(rrule, forKey: .rrule)
        }
    }

    /// Map a reminder's EventKit rules. Nil when there are none.
    ///
    /// Exactly one rule that `RecurrenceRule.from(_:)` can express is `.supported`. Anything else,
    /// including several rules, is `.unsupported`: never approximated, so a later write can't
    /// silently rewrite the user's rule.
    public static func from(rules: [EKRecurrenceRule]?) -> ReminderRecurrence? {
        guard let rules = rules, !rules.isEmpty else { return nil }
        if rules.count == 1, let rule = RecurrenceRule.from(rules[0]) {
            return .supported(rule)
        }
        return .unsupported(rrule: rules.map { rrule(of: $0) }.joined(separator: "\n"))
    }

    /// The RRULE text of a rule, e.g. `FREQ=MONTHLY;INTERVAL=1;BYDAY=MO`
    public static func rrule(of rule: EKRecurrenceRule) -> String {
        rrule(fromDescription: rule.description)
    }

    /// EventKit describes a rule as `EKRecurrenceRule <0x...> RRULE FREQ=...`. Returns the part
    /// after "RRULE ", or the whole description if it isn't in that shape.
    public static func rrule(fromDescription description: String) -> String {
        guard let marker = description.range(of: "RRULE ") else { return description }
        let rrule = description[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return rrule.isEmpty ? description : rrule
    }
}
