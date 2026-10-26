import Foundation
import UserNotifications

struct ReminderItem {
    let id: String
    let title: String
    let body: String
    /// Calendar weekday: 1 = Sunday ... 7 = Saturday
    let weekday: Int
    let hour: Int
    let minute: Int
}

/// A one-off reminder at an exact time (used for assignment due dates).
struct OneOffReminder {
    let id: String
    let title: String
    let body: String
    let fireDate: Date
}

enum ReminderService {
    /// Asks for permission only if the person hasn't been asked yet.
    static func requestAuthorizationIfNeeded() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = await requestAuthorization()
        }
    }

    /// A reminder a day before and an hour before each unfinished assignment.
    @MainActor
    static func assignmentItems(from assignments: [Assignment], subjects: [Subject], now: Date = Date()) -> [OneOffReminder] {
        var result: [OneOffReminder] = []
        for a in assignments where !a.isCompleted && a.dueDate > now {
            let subject = subjects.first { $0.id == a.subjectID }?.name
            let detail = subject.map { "\($0) · " } ?? ""
            let dayBefore = a.dueDate.addingTimeInterval(-24 * 60 * 60)
            if dayBefore > now {
                result.append(OneOffReminder(
                    id: "assignment-\(a.id.uuidString)-day",
                    title: "Due tomorrow: \(a.title)",
                    body: "\(detail)Due at \(a.dueDate.formatted(date: .omitted, time: .shortened))",
                    fireDate: dayBefore
                ))
            }
            let hourBefore = a.dueDate.addingTimeInterval(-60 * 60)
            if hourBefore > now {
                result.append(OneOffReminder(
                    id: "assignment-\(a.id.uuidString)-hour",
                    title: "Due in 1 hour: \(a.title)",
                    body: "\(detail)Hand it in by \(a.dueDate.formatted(date: .omitted, time: .shortened))",
                    fireDate: hourBefore
                ))
            }
        }
        return result.sorted { $0.fireDate < $1.fireDate }
    }

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Builds weekly reminders from the timetable. Must be called on the main actor
    /// because it reads SwiftData objects.
    @MainActor
    static func items(from entries: [TimetableEntry]) -> [ReminderItem] {
        var result: [ReminderItem] = []
        for e in entries where e.isActive {
            guard let subject = e.subject, !subject.isArchived else { continue }
            let parts = e.startTime.split(separator: ":")
            guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]) else { continue }

            // Android: 1 = Monday ... 7 = Sunday  ->  Calendar: 1 = Sunday ... 7 = Saturday
            var weekday = e.dayOfWeek % 7 + 1
            var total = h * 60 + m - max(0, e.reminderMinutes)
            if total < 0 {
                total += 24 * 60
                weekday = weekday == 1 ? 7 : weekday - 1
            }

            let room = e.roomOverride.isEmpty ? subject.room : e.roomOverride
            var body = "Starts at \(DateUtils.displayTime(e.startTime))"
            if !room.isEmpty { body += " · \(room)" }

            result.append(ReminderItem(
                id: "class-\(e.id.uuidString)",
                title: subject.name,
                body: body,
                weekday: weekday,
                hour: total / 60,
                minute: total % 60
            ))
        }
        return result
    }

    static func reschedule(
        items: [ReminderItem],
        enabled: Bool,
        oneOff: [OneOffReminder] = [],
        oneOffEnabled: Bool = false
    ) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard enabled || oneOffEnabled else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        // iOS keeps at most 64 pending local notifications: the soonest
        // assignment reminders first, then weekly class reminders.
        var budget = 60
        if oneOffEnabled {
            for item in oneOff.prefix(30) {
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
                budget -= 1
            }
        }
        guard enabled else { return }

        for item in items.prefix(budget) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default

            var components = DateComponents()
            components.weekday = item.weekday
            components.hour = item.hour
            components.minute = item.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
