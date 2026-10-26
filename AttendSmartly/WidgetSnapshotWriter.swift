import Foundation
import SwiftData
import WidgetKit

/// Builds the widget's snapshot from the app's data and asks WidgetKit to refresh.
enum WidgetSnapshotWriter {
    @MainActor
    static func update(_ context: ModelContext, now: Date = Date()) {
        guard AppGroup.containerURL != nil else { return }
        guard let snapshot = try? makeSnapshot(context, now: now) else { return }
        if AppGroup.save(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @MainActor
    static func makeSnapshot(_ context: ModelContext, now: Date = Date()) throws -> WidgetSnapshot {
        let defaults = UserDefaults.standard
        let semester = SemesterRange(
            enabled: defaults.bool(forKey: PrefKey.semesterEnabled),
            start: defaults.string(forKey: PrefKey.semesterStart) ?? "",
            end: defaults.string(forKey: PrefKey.semesterEnd) ?? ""
        )

        let subjects = try context.fetch(FetchDescriptor<Subject>())
        let sessions = try context.fetch(FetchDescriptor<AttendanceSession>())
        let entries = try context.fetch(FetchDescriptor<TimetableEntry>())
        let holidays = try context.fetch(FetchDescriptor<Holiday>())

        // Same numbers as the Home screen.
        let active = subjects.filter { !$0.isArchived }
        let statuses = sessions
            .filter { semester.includes($0.sessionDate) }
            .flatMap { session -> [AttendanceStatus] in
                guard let subject = session.subject, !subject.isArchived else { return [] }
                return session.units.map { $0.status }
            }
        let target = active.isEmpty ? 75 : active.map { $0.targetPercentage }.reduce(0, +) / Double(active.count)
        let summary = AttendanceCalculator.summary(statuses: statuses, target: target)

        let today = DateUtils.isoString(now)
        let horizon = DateUtils.isoString(Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now)

        var classes: [WidgetSnapshot.ClassItem] = []
        for entry in entries where entry.isActive {
            guard let subject = entry.subject, !subject.isArchived else { continue }
            classes.append(.init(
                weekday: entry.dayOfWeek,
                date: nil,
                startTime: entry.startTime,
                endTime: entry.endTime,
                name: subject.name,
                room: entry.roomOverride.isEmpty ? subject.room : entry.roomOverride,
                colorARGB: subject.colorValue,
                startDate: entry.startDate,
                endDate: entry.endDate
            ))
        }

        var skipped: [String] = []
        for session in sessions where session.sessionDate >= today && session.sessionDate <= horizon {
            guard let subject = session.subject, !subject.isArchived else { continue }
            let allCancelled = !session.units.isEmpty && session.units.allSatisfy { $0.status == .cancelled }
            if session.timetableEntryID == nil {
                // Extra or rescheduled class on a specific day.
                if !allCancelled {
                    classes.append(.init(
                        weekday: nil,
                        date: session.sessionDate,
                        startTime: session.startTime,
                        endTime: session.endTime,
                        name: subject.name,
                        room: subject.room,
                        colorARGB: subject.colorValue,
                        startDate: "",
                        endDate: ""
                    ))
                }
            } else if allCancelled {
                skipped.append("\(session.sessionDate)|\(session.startTime)|\(subject.name)")
            }
        }

        var holidayMap: [String: String] = [:]
        for holiday in holidays where holiday.date >= today {
            holidayMap[holiday.date] = holiday.title
        }

        return WidgetSnapshot(
            generatedAt: now,
            userName: defaults.string(forKey: PrefKey.userName) ?? "Marshal",
            percentage: summary.percentage,
            target: summary.target,
            present: summary.present,
            conducted: summary.conducted,
            message: summary.message,
            classes: classes,
            holidays: holidayMap,
            skipped: skipped
        )
    }
}
