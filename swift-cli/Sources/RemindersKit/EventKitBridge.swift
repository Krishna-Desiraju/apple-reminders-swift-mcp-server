import Foundation
import EventKit

/// Bridge between our app and EventKit framework
/// Handles permissions and provides access to EKEventStore
public class EventKitBridge {
    public static let shared = EventKitBridge()
    
    private let eventStore = EKEventStore()
    private var hasRequestedAccess = false
    
    private init() {}
    
    /// Request access to reminders
    /// - Returns: true if access granted, false otherwise
    @available(macOS 13.0, *)
    public func requestAccess() async throws -> Bool {
        // Check if we need to request full access (macOS 14+) or legacy access
        if #available(macOS 14.0, *) {
            return try await eventStore.requestFullAccessToReminders()
        } else {
            return try await eventStore.requestAccess(to: .reminder)
        }
    }
    
    /// Get the event store instance
    public func getEventStore() -> EKEventStore {
        return eventStore
    }
    
    /// Get the default reminders calendar (list)
    public func getDefaultRemindersList() -> EKCalendar? {
        return eventStore.defaultCalendarForNewReminders()
    }
    
    /// Get all reminder calendars (lists)
    public func getAllReminderLists() -> [EKCalendar] {
        return eventStore.calendars(for: .reminder)
    }
    
    /// Find a calendar by name
    public func findList(byName name: String) -> EKCalendar? {
        let calendars = eventStore.calendars(for: .reminder)
        return calendars.first { $0.title.lowercased() == name.lowercased() }
    }
    
    /// Find all calendars matching a name (case-insensitive)
    public func findLists(byName name: String) -> [EKCalendar] {
        let calendars = eventStore.calendars(for: .reminder)
        return calendars.filter { $0.title.lowercased() == name.lowercased() }
    }
    
    /// Find a reminder calendar by ID
    public func findList(byId id: String) -> EKCalendar? {
        guard let calendar = eventStore.calendar(withIdentifier: id),
              calendar.allowedEntityTypes.contains(.reminder) else {
            return nil
        }
        return calendar
    }
}

