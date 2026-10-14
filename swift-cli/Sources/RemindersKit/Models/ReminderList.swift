import Foundation
import EventKit
import CoreGraphics

/// Represents a reminder list (calendar in EventKit terminology)
public struct ReminderList: Codable {
    public let id: String
    public let title: String
    /// Hex color in `#RRGGBB` form
    public let color: String?
    public let type: String
    /// Account the list belongs to (e.g. "iCloud", "On My Mac")
    public let source: String?
    public let allowsContentModifications: Bool

    /// Initialize from EKCalendar
    public init(from calendar: EKCalendar) {
        self.id = calendar.calendarIdentifier
        self.title = calendar.title
        self.color = calendar.cgColor.flatMap(ReminderList.hexString(from:))
        self.type = calendar.type.description
        self.source = calendar.source?.title
        self.allowsContentModifications = calendar.allowsContentModifications
    }

    /// Manual initializer for testing
    public init(
        id: String,
        title: String,
        color: String? = nil,
        type: String = "Local",
        source: String? = nil,
        allowsContentModifications: Bool = true
    ) {
        self.id = id
        self.title = title
        self.color = color
        self.type = type
        self.source = source
        self.allowsContentModifications = allowsContentModifications
    }

    /// Convert a CGColor to `#RRGGBB`
    static func hexString(from color: CGColor) -> String? {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: srgb, intent: .defaultIntent, options: nil),
              let components = converted.components,
              components.count >= 3 else {
            return nil
        }
        let rgb = components.prefix(3).map { Int((max(0, min(1, $0)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", rgb[0], rgb[1], rgb[2])
    }

    /// Parse `#RRGGBB` or `RRGGBB` into a CGColor
    static func cgColor(fromHex hex: String) -> CGColor? {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else {
            return nil
        }
        return CGColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// Extension to make EKCalendarType convertible to String
extension EKCalendarType: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .local:
            return "Local"
        case .calDAV:
            return "CalDAV"
        case .exchange:
            return "Exchange"
        case .subscription:
            return "Subscription"
        case .birthday:
            return "Birthday"
        @unknown default:
            return "Unknown"
        }
    }
}
