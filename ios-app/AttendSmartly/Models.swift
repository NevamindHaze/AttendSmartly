import Foundation
import SwiftData

enum AttendanceStatus: String, Codable, CaseIterable {
    case unmarked = "UNMARKED"
    case present = "PRESENT"
    case absent = "ABSENT"
    case bunked = "BUNKED"
    case cancelled = "CANCELLED"
}

@Model
final class Subject {
    @Attribute(.unique) var id: UUID
    var name: String
    var attendanceTarget: Double
    var isArchived: Bool
    var notes: String
    var colorIdentifier: String

    @Relationship(deleteRule: .cascade, inverse: \TimetableEntry.subject)
    var timetableEntries: [TimetableEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \AttendanceSession.subject)
    var attendanceSessions: [AttendanceSession] = []

    init(
        id: UUID = UUID(),
        name: String,
        attendanceTarget: Double = 75,
        isArchived: Bool = false,
        notes: String = "",
        colorIdentifier: String = "green"
    ) {
        self.id = id
        self.name = name
        self.attendanceTarget = attendanceTarget
        self.isArchived = isArchived
        self.notes = notes
        self.colorIdentifier = colorIdentifier
    }
}

@Model
final class TimetableEntry {
    @Attribute(.unique) var id: UUID
    var weekday: Int
    var startTime: String
    var endTime: String
    var startDate: Date?
    var endDate: Date?

    var subject: Subject?

    init(
        id: UUID = UUID(),
        subject: Subject? = nil,
        weekday: Int,
        startTime: String,
        endTime: String,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.id = id
        self.subject = subject
        self.weekday = weekday
        self.startTime = startTime
        self.endTime = endTime
        self.startDate = startDate
        self.endDate = endDate
    }
}

@Model
final class AttendanceSession {
    @Attribute(.unique) var id: UUID
    var date: Date
    var isCancelled: Bool

    var subject: Subject?

    @Relationship(deleteRule: .cascade, inverse: \AttendanceUnit.session)
    var units: [AttendanceUnit] = []

    init(
        id: UUID = UUID(),
        date: Date,
        subject: Subject? = nil,
        isCancelled: Bool = false
    ) {
        self.id = id
        self.date = date
        self.subject = subject
        self.isCancelled = isCancelled
    }
}

@Model
final class AttendanceUnit {
    @Attribute(.unique) var id: UUID
    var status: AttendanceStatus

    var session: AttendanceSession?

    init(
        id: UUID = UUID(),
        session: AttendanceSession? = nil,
        status: AttendanceStatus = .unmarked
    ) {
        self.id = id
        self.session = session
        self.status = status
    }
}

@Model
final class Holiday {
    @Attribute(.unique) var id: UUID
    var date: Date
    var name: String
    var notes: String?

    init(
        id: UUID = UUID(),
        date: Date,
        name: String,
        notes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.name = name
        self.notes = notes
    }
}
