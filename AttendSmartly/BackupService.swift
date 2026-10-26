import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - JSON shapes (same keys as the Android backup)

struct BackupFile: Codable {
    var format: String?
    var version: Int?
    var exportedAt: Int64?
    var subjects: [BSubject]?
    var timetableEntries: [BEntry]?
    var sessions: [BSession]?
    var units: [BUnit]?
    var holidays: [BHoliday]?
}

struct BSubject: Codable {
    var id: Int?
    var name: String?
    var code: String?
    var type: String?
    var teacherName: String?
    var room: String?
    var colorValue: Int64?
    var iconName: String?
    var targetPercentage: Double?
    var notes: String?
    var isArchived: Bool?
    var defaultSessionDurationMinutes: Int?
    var attendanceUnitMinutes: Int?
    var defaultAttendanceUnits: Int?
    var defaultReminderMinutes: Int?
    var locationRadiusMeters: Int?
    var createdAt: Int64?
    var updatedAt: Int64?
}

struct BEntry: Codable {
    var id: Int?
    var subjectId: Int?
    var dayOfWeek: Int?
    var startTime: String?
    var endTime: String?
    var startDate: String?
    var endDate: String?
    var repeatType: String?
    var attendanceUnitCount: Int?
    var roomOverride: String?
    var teacherOverride: String?
    var notes: String?
    var isActive: Bool?
    var reminderMinutes: Int?
    var locationRadiusMeters: Int?
    var createdAt: Int64?
    var updatedAt: Int64?
}

struct BSession: Codable {
    var id: Int?
    var subjectId: Int?
    var timetableEntryId: Int?
    var sessionDate: String?
    var startTime: String?
    var endTime: String?
    var expectedUnitCount: Int?
    var notes: String?
    var isRescheduled: Bool?
    var autoMarked: Bool?
    var createdAt: Int64?
    var updatedAt: Int64?
}

struct BUnit: Codable {
    var id: Int?
    var sessionId: Int?
    var unitIndex: Int?
    var status: String?
    var markedAt: Int64?
    var updatedAt: Int64?
}

struct BHoliday: Codable {
    var id: Int?
    var date: String?
    var title: String?
    var notes: String?
}

struct ImportResult {
    var subjects = 0
    var entries = 0
    var sessions = 0
    var units = 0
    var holidays = 0
    var skipped = 0
    var alreadyPresent = 0

    var summary: String {
        var text = "Imported \(subjects) subjects, \(entries) timetable entries, \(sessions) sessions, \(units) attendance units and \(holidays) holidays."
        if alreadyPresent > 0 { text += " Left out \(alreadyPresent) items that were already in the app." }
        if skipped > 0 { text += " Skipped \(skipped) items that referenced missing data." }
        return text
    }
}

enum BackupError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let m): return m }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Service

enum BackupService {
    private static func text(_ value: String?, _ fallback: String = "") -> String {
        let v = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return v.isEmpty ? fallback : v
    }

    private static func date(fromMillis ms: Int64?) -> Date {
        guard let ms = ms, ms > 0 else { return Date() }
        return Date(timeIntervalSince1970: Double(ms) / 1000)
    }

    private static func millis(_ d: Date) -> Int64 {
        Int64(d.timeIntervalSince1970 * 1000)
    }

    static func wipe(_ context: ModelContext) throws {
        for s in try context.fetch(FetchDescriptor<Subject>()) { context.delete(s) }
        try context.save()
        for e in try context.fetch(FetchDescriptor<TimetableEntry>()) { context.delete(e) }
        for s in try context.fetch(FetchDescriptor<AttendanceSession>()) { context.delete(s) }
        for u in try context.fetch(FetchDescriptor<AttendanceUnit>()) { context.delete(u) }
        for h in try context.fetch(FetchDescriptor<Holiday>()) { context.delete(h) }
        try context.save()
    }

    static func importData(_ raw: Data, into context: ModelContext, replaceExisting: Bool) throws -> ImportResult {
        var data = raw
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data.removeFirst(3) }

        let backup: BackupFile
        do {
            backup = try JSONDecoder().decode(BackupFile.self, from: data)
        } catch {
            throw BackupError.invalid("This file isn't a valid AttendSmartly backup. (\(error.localizedDescription))")
        }
        guard backup.subjects != nil || backup.timetableEntries != nil || backup.sessions != nil else {
            throw BackupError.invalid("No AttendSmartly data was found in this file.")
        }

        // A shared-timetable package only holds subjects + timetable, so never wipe attendance for it.
        let isTimetablePackage = (backup.format ?? "").hasPrefix("AttendSmartly_TIMETABLE")
        if replaceExisting && !isTimetablePackage { try wipe(context) }

        var result = ImportResult()
        var subjectMap: [Int: Subject] = [:]
        var entryMap: [Int: TimetableEntry] = [:]
        var sessionMap: [Int: AttendanceSession] = [:]
        var duplicateSessionIDs = Set<Int>()

        // Merge safeguard: a subject that already exists (same name, ignoring case and spaces)
        // is reused instead of copied, and its classes and records are only added if missing.
        func key(_ name: String) -> String {
            name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        var existingByName: [String: Subject] = [:]
        for subject in try context.fetch(FetchDescriptor<Subject>()) {
            existingByName[key(subject.name)] = existingByName[key(subject.name)] ?? subject
        }
        var reused = Set<UUID>()

        for (i, b) in (backup.subjects ?? []).enumerated() {
            if let existing = existingByName[key(text(b.name, "Unnamed Subject"))] {
                subjectMap[b.id ?? -(i + 1)] = existing
                reused.insert(existing.id)
                result.alreadyPresent += 1
                continue
            }
            let s = Subject(name: text(b.name, "Unnamed Subject"))
            s.code = text(b.code)
            s.type = text(b.type, "Lecture")
            s.teacherName = text(b.teacherName)
            s.room = text(b.room)
            if let c = b.colorValue, c != 0 { s.colorValue = Int(c) }
            s.iconName = text(b.iconName, "Book")
            if let t = b.targetPercentage, t > 0 { s.targetPercentage = t }
            s.notes = text(b.notes)
            s.isArchived = b.isArchived ?? false
            if let v = b.defaultSessionDurationMinutes, v > 0 { s.defaultSessionDurationMinutes = v }
            if let v = b.attendanceUnitMinutes, v > 0 { s.attendanceUnitMinutes = v }
            if let v = b.defaultAttendanceUnits, v > 0 { s.defaultAttendanceUnits = v }
            if let v = b.defaultReminderMinutes, v >= 0 { s.defaultReminderMinutes = v }
            s.createdAt = date(fromMillis: b.createdAt)
            context.insert(s)
            subjectMap[b.id ?? -(i + 1)] = s
            result.subjects += 1
        }

        for (i, b) in (backup.timetableEntries ?? []).enumerated() {
            guard let sid = b.subjectId, let subject = subjectMap[sid] else { result.skipped += 1; continue }
            if reused.contains(subject.id), let match = subject.timetableEntries.first(where: {
                $0.dayOfWeek == (b.dayOfWeek ?? 0)
                    && $0.startTime == text(b.startTime, "09:00")
                    && $0.endTime == text(b.endTime, "10:00")
            }) {
                entryMap[b.id ?? -(i + 1)] = match
                result.alreadyPresent += 1
                continue
            }
            let e = TimetableEntry()
            e.dayOfWeek = (1...7).contains(b.dayOfWeek ?? 0) ? (b.dayOfWeek ?? 1) : 1
            e.startTime = text(b.startTime, "09:00")
            e.endTime = text(b.endTime, "10:00")
            e.startDate = text(b.startDate)
            e.endDate = text(b.endDate)
            e.repeatType = text(b.repeatType, "WEEKLY")
            e.attendanceUnitCount = max(1, b.attendanceUnitCount ?? 1)
            e.roomOverride = text(b.roomOverride)
            e.teacherOverride = text(b.teacherOverride)
            e.notes = text(b.notes)
            e.isActive = b.isActive ?? true
            e.reminderMinutes = max(0, b.reminderMinutes ?? 10)
            context.insert(e)
            e.subject = subject
            entryMap[b.id ?? -(i + 1)] = e
            result.entries += 1
        }

        for (i, b) in (backup.sessions ?? []).enumerated() {
            guard let sid = b.subjectId, let subject = subjectMap[sid] else { result.skipped += 1; continue }
            if reused.contains(subject.id), subject.sessions.contains(where: {
                $0.sessionDate == text(b.sessionDate) && $0.startTime == text(b.startTime, "09:00")
            }) {
                duplicateSessionIDs.insert(b.id ?? -(i + 1))
                result.alreadyPresent += 1
                continue
            }
            let s = AttendanceSession(
                sessionDate: text(b.sessionDate, DateUtils.isoString(Date())),
                startTime: text(b.startTime, "09:00"),
                endTime: text(b.endTime, "10:00"),
                expectedUnitCount: b.expectedUnitCount ?? 1
            )
            s.notes = text(b.notes)
            s.isRescheduled = b.isRescheduled ?? false
            s.createdAt = date(fromMillis: b.createdAt)
            if let eid = b.timetableEntryId { s.timetableEntryID = entryMap[eid]?.id }
            context.insert(s)
            s.subject = subject
            sessionMap[b.id ?? -(i + 1)] = s
            result.sessions += 1
        }

        for b in backup.units ?? [] {
            if let sid = b.sessionId, duplicateSessionIDs.contains(sid) { continue }
            guard let sid = b.sessionId, let session = sessionMap[sid] else { result.skipped += 1; continue }
            let u = AttendanceUnit(unitIndex: max(0, b.unitIndex ?? 0), status: AttendanceStatus.parse(b.status))
            u.markedAt = date(fromMillis: b.markedAt)
            context.insert(u)
            u.session = session
            result.units += 1
        }

        let existingHolidays = Set(try context.fetch(FetchDescriptor<Holiday>()).map { $0.date + "|" + key($0.title) })
        for b in backup.holidays ?? [] {
            let holidayDate = text(b.date, DateUtils.isoString(Date()))
            if existingHolidays.contains(holidayDate + "|" + key(text(b.title, "Holiday"))) {
                result.alreadyPresent += 1
                continue
            }
            let h = Holiday(date: holidayDate, title: text(b.title, "Holiday"))
            h.notes = text(b.notes)
            context.insert(h)
            result.holidays += 1
        }

        try context.save()
        return result
    }

    static func exportData(from context: ModelContext) throws -> Data {
        let subjects = try context.fetch(FetchDescriptor<Subject>(sortBy: [SortDescriptor(\.createdAt)]))
        let entries = try context.fetch(FetchDescriptor<TimetableEntry>())
        let sessions = try context.fetch(FetchDescriptor<AttendanceSession>(sortBy: [SortDescriptor(\.createdAt)]))
        let holidays = try context.fetch(FetchDescriptor<Holiday>())
        let now = millis(Date())

        var subjectIds: [UUID: Int] = [:]
        var entryIds: [UUID: Int] = [:]
        var sessionIds: [UUID: Int] = [:]

        var file = BackupFile()
        file.version = 1
        file.exportedAt = now

        file.subjects = subjects.enumerated().map { (i, s) in
            subjectIds[s.id] = i + 1
            return BSubject(
                id: i + 1, name: s.name, code: s.code, type: s.type, teacherName: s.teacherName,
                room: s.room, colorValue: Int64(s.colorValue), iconName: s.iconName,
                targetPercentage: s.targetPercentage, notes: s.notes, isArchived: s.isArchived,
                defaultSessionDurationMinutes: s.defaultSessionDurationMinutes,
                attendanceUnitMinutes: s.attendanceUnitMinutes,
                defaultAttendanceUnits: s.defaultAttendanceUnits,
                defaultReminderMinutes: s.defaultReminderMinutes,
                locationRadiusMeters: 50,
                createdAt: millis(s.createdAt), updatedAt: now
            )
        }

        let validEntries = entries.filter { $0.subject != nil && subjectIds[$0.subject!.id] != nil }
        file.timetableEntries = validEntries.enumerated().map { (i, e) in
            entryIds[e.id] = i + 1
            return BEntry(
                id: i + 1, subjectId: subjectIds[e.subject!.id], dayOfWeek: e.dayOfWeek,
                startTime: e.startTime, endTime: e.endTime, startDate: e.startDate, endDate: e.endDate,
                repeatType: e.repeatType, attendanceUnitCount: e.attendanceUnitCount,
                roomOverride: e.roomOverride, teacherOverride: e.teacherOverride, notes: e.notes,
                isActive: e.isActive, reminderMinutes: e.reminderMinutes, locationRadiusMeters: 50,
                createdAt: now, updatedAt: now
            )
        }

        let validSessions = sessions.filter { $0.subject != nil && subjectIds[$0.subject!.id] != nil }
        file.sessions = validSessions.enumerated().map { (i, s) in
            sessionIds[s.id] = i + 1
            return BSession(
                id: i + 1, subjectId: subjectIds[s.subject!.id],
                timetableEntryId: s.timetableEntryID.flatMap { entryIds[$0] },
                sessionDate: s.sessionDate, startTime: s.startTime, endTime: s.endTime,
                expectedUnitCount: s.expectedUnitCount, notes: s.notes,
                isRescheduled: s.isRescheduled, autoMarked: false,
                createdAt: millis(s.createdAt), updatedAt: now
            )
        }

        var units: [BUnit] = []
        for s in validSessions {
            for u in s.units.sorted(by: { $0.unitIndex < $1.unitIndex }) {
                units.append(BUnit(
                    id: units.count + 1, sessionId: sessionIds[s.id], unitIndex: u.unitIndex,
                    status: u.status == .bunked ? "ABSENT" : u.statusRaw,
                    markedAt: millis(u.markedAt), updatedAt: now
                ))
            }
        }
        file.units = units

        file.holidays = holidays.enumerated().map { (i, h) in
            BHoliday(id: i + 1, date: h.date, title: h.title, notes: h.notes)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }
}
