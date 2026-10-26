import Foundation
import SwiftData
import SwiftUI

/// Something to hand in by a due date. Linked to a subject by its id, so adding
/// assignments never changes how existing subjects are stored.
@Model
final class Assignment {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var subjectID: UUID?
    var dueDate: Date = Date()
    /// The day it was set. The due date normally follows from this.
    var assignedDate: Date = Date()
    /// true when the due date was picked by hand instead of "assigned + deadline".
    var hasCustomDue: Bool = false
    /// When it was marked done. nil while it's still to do.
    var completedAt: Date?
    var createdAt: Date = Date()

    init(title: String, dueDate: Date, subjectID: UUID? = nil, assignedDate: Date? = nil) {
        self.title = title
        self.dueDate = dueDate
        self.subjectID = subjectID
        self.assignedDate = assignedDate ?? dueDate
    }

    /// Default number of days you have to hand work in (Settings → Assignments).
    static var deadlineDays: Int {
        let value = UserDefaults.standard.integer(forKey: PrefKey.assignmentDeadlineDays)
        return value > 0 ? value : 7
    }

    /// The end of the day, `days` days after it was assigned: set on Monday 26 with
    /// 7 days means due Monday 2 at 11:59 PM.
    static func dueDate(assignedOn assigned: Date, days: Int, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: assigned)
        let day = calendar.date(byAdding: .day, value: days, to: start) ?? start
        return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? day
    }

    /// Whole days left until the due date, counting today as 0 when it's due today.
    func daysLeft(now: Date = Date(), calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: dueDate)).day ?? 0
    }

    var isCompleted: Bool { completedAt != nil }

    func status(now: Date = Date()) -> AssignmentStatus {
        AssignmentStatus.of(due: dueDate, completedAt: completedAt, now: now)
    }
}

enum AssignmentStatus: Equatable {
    case overdue(by: TimeInterval)
    case dueToday
    case dueSoon        // within the next 3 days
    case upcoming
    case doneOnTime
    case doneLate(by: TimeInterval)

    static let soonWindow: TimeInterval = 3 * 24 * 60 * 60

    static func of(due: Date, completedAt: Date?, now: Date, calendar: Calendar = .current) -> AssignmentStatus {
        if let done = completedAt {
            return done <= due ? .doneOnTime : .doneLate(by: done.timeIntervalSince(due))
        }
        if now > due { return .overdue(by: now.timeIntervalSince(due)) }
        if calendar.isDate(due, inSameDayAs: now) { return .dueToday }
        if due.timeIntervalSince(now) <= soonWindow { return .dueSoon }
        return .upcoming
    }

    /// Order for sorting the list: most urgent first.
    var rank: Int {
        switch self {
        case .overdue: return 0
        case .dueToday: return 1
        case .dueSoon: return 2
        case .upcoming: return 3
        case .doneLate, .doneOnTime: return 4
        }
    }

    var isOpen: Bool { rank < 4 }

    var label: String {
        switch self {
        case .overdue(let by): return "Overdue by \(Self.duration(by))"
        case .dueToday: return "Due today"
        case .dueSoon: return "Due soon"
        case .upcoming: return "Upcoming"
        case .doneOnTime: return "Done on time"
        case .doneLate(let by): return "Done \(Self.duration(by)) late"
        }
    }

    var symbol: String {
        switch self {
        case .overdue: return "exclamationmark.circle.fill"
        case .dueToday: return "clock.badge.exclamationmark"
        case .dueSoon: return "clock"
        case .upcoming: return "calendar"
        case .doneOnTime: return "checkmark.seal.fill"
        case .doneLate: return "checkmark.circle"
        }
    }

    /// Strong colour for badges.
    var tint: Color {
        switch self {
        case .overdue, .doneLate: return DashboardPalette.coral
        case .dueToday, .dueSoon: return DashboardPalette.amber
        case .upcoming: return DashboardPalette.blue
        case .doneOnTime: return DashboardPalette.green
        }
    }

    /// Soft tile colour, matching the rest of the app.
    var tile: Color {
        switch self {
        case .overdue: return Pastel.pink
        case .dueToday, .dueSoon: return Pastel.butter
        case .upcoming: return Pastel.sky
        case .doneOnTime: return Pastel.mint
        case .doneLate: return Pastel.peach
        }
    }

    /// "3 days", "5 hours", "20 minutes".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return minutes <= 1 ? "a minute" : "\(minutes) minutes" }
        let hours = minutes / 60
        if hours < 24 { return hours == 1 ? "1 hour" : "\(hours) hours" }
        let days = hours / 24
        return days == 1 ? "1 day" : "\(days) days"
    }
}

enum AssignmentFormat {
    /// "Today, 11:59 PM", "Tomorrow, 9:00 AM", "Fri 31 Oct, 5:00 PM".
    static func due(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "Today, \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow, \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday, \(time)" }
        let day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return "\(day), \(time)"
    }
}
