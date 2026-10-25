import Foundation
import SwiftData

enum AttendanceStatus: String, CaseIterable {
    case unmarked = "UNMARKED"
    case present = "PRESENT"
    case absent = "ABSENT"
    case bunked = "BUNKED"
    case cancelled = "CANCELLED"

    static func parse(_ raw: String?) -> AttendanceStatus {
        switch (raw ?? "").trimmingCharacters(in: .whitespaces).uppercased() {
        case "PRESENT", "ATTENDED", "YES": return .present
        case "ABSENT", "MISSED", "NO": return .absent
        case "BUNKED": return .bunked
        case "CANCELLED", "CANCELED", "HOLIDAY": return .cancelled
        default: return .unmarked
        }
    }
}

/// Mirrors the Android SubjectEntity. Dates are ISO strings (yyyy-MM-dd) and
/// times are "HH:mm" strings, exactly like the Android backup format.
@Model
final class Subject {
    var id: UUID = UUID()
    var name: String = ""
    var code: String = ""
    var type: String = "Lecture"
    var teacherName: String = ""
    var room: String = ""
    var colorValue: Int = 0xFF2196F3
    var iconName: String = "Book"
    var targetPercentage: Double = 75
    var notes: String = ""
    var isArchived: Bool = false
    var defaultSessionDurationMinutes: Int = 60
    var attendanceUnitMinutes: Int = 60
    var defaultAttendanceUnits: Int = 1
    var defaultReminderMinutes: Int = 10
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \TimetableEntry.subject)
    var timetableEntries: [TimetableEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \AttendanceSession.subject)
    var sessions: [AttendanceSession] = []

    init(name: String) {
        self.name = name
    }
}

@Model
final class TimetableEntry {
    var id: UUID = UUID()
    /// 1 = Monday ... 7 = Sunday (same as Android)
    var dayOfWeek: Int = 1
    var startTime: String = "09:00"
    var endTime: String = "10:00"
    var startDate: String = ""
    var endDate: String = ""
    var repeatType: String = "WEEKLY"
    var attendanceUnitCount: Int = 1
    var roomOverride: String = ""
    var teacherOverride: String = ""
    var notes: String = ""
    var isActive: Bool = true
    var reminderMinutes: Int = 10
    var subject: Subject?

    init() {}
}

@Model
final class AttendanceSession {
    var id: UUID = UUID()
    var sessionDate: String = ""
    var startTime: String = "09:00"
    var endTime: String = "10:00"
    var expectedUnitCount: Int = 1
    var notes: String = ""
    var isRescheduled: Bool = false
    var timetableEntryID: UUID?
    var createdAt: Date = Date()
    var subject: Subject?

    @Relationship(deleteRule: .cascade, inverse: \AttendanceUnit.session)
    var units: [AttendanceUnit] = []

    init(sessionDate: String, startTime: String, endTime: String, expectedUnitCount: Int) {
        self.sessionDate = sessionDate
        self.startTime = startTime
        self.endTime = endTime
        self.expectedUnitCount = max(1, expectedUnitCount)
    }
}

@Model
final class AttendanceUnit {
    var id: UUID = UUID()
    var unitIndex: Int = 0
    var statusRaw: String = AttendanceStatus.unmarked.rawValue
    var markedAt: Date = Date()
    var session: AttendanceSession?

    var status: AttendanceStatus {
        get { AttendanceStatus(rawValue: statusRaw) ?? .unmarked }
        set { statusRaw = newValue.rawValue }
    }

    init(unitIndex: Int, status: AttendanceStatus) {
        self.unitIndex = unitIndex
        self.statusRaw = status.rawValue
    }
}

@Model
final class Holiday {
    var id: UUID = UUID()
    var date: String = ""
    var title: String = "Holiday"
    var notes: String = ""

    init(date: String, title: String) {
        self.date = date
        self.title = title
    }
}
