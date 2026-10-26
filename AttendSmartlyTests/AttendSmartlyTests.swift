import XCTest
import SwiftData
import CoreGraphics
@testable import AttendSmartly

final class AttendSmartlyTests: XCTestCase {
    func testAttendanceSummaryCountsPresentAndAbsentUnitsButExcludesCancelled() {
        let summary = AttendanceCalculator.summary(
            statuses: [.present, .present, .absent, .bunked, .cancelled, .unmarked]
        )

        XCTAssertEqual(summary.present, 2)
        XCTAssertEqual(summary.absent, 2)
        XCTAssertEqual(summary.cancelled, 1)
        XCTAssertEqual(summary.conducted, 4)
        XCTAssertEqual(summary.percentage, 50, accuracy: 0.001)
    }

    func testSafeBunkAndRecoveryBoundaries() {
        let safeBunk = AttendanceCalculator.summary(
            statuses: Array(repeating: .present, count: 12) + Array(repeating: .absent, count: 3),
            target: 75
        )
        XCTAssertEqual(safeBunk.percentage, 80, accuracy: 0.001)
        XCTAssertEqual(safeBunk.safeBunks, 1)

        let recovery = AttendanceCalculator.summary(
            statuses: Array(repeating: .present, count: 3) + Array(repeating: .absent, count: 2),
            target: 75
        )
        XCTAssertEqual(recovery.requiredUnits, 3)
    }

    func testOneHundredPercentTargetCannotRecoverAfterAnAbsence() {
        let summary = AttendanceCalculator.summary(statuses: [.present, .absent], target: 100)

        XCTAssertEqual(summary.requiredUnits, Int.max)
        XCTAssertEqual(summary.safeBunks, 0)
    }

    func testScheduleDateBoundsAreInclusiveAndRespectWeekdayAndActiveState() throws {
        let selectedDate = try makeDate("2026-10-26")
        let entry = TimetableEntry()
        entry.dayOfWeek = DateUtils.dayOfWeek(selectedDate)
        entry.startDate = "2026-10-26"
        entry.endDate = "2026-10-26"

        XCTAssertTrue(DateUtils.isScheduled(entry, on: selectedDate), "Both date boundaries are inclusive.")

        entry.startDate = "2026-10-27"
        XCTAssertFalse(DateUtils.isScheduled(entry, on: selectedDate), "A future start date must hide the class.")

        entry.startDate = ""
        entry.endDate = "2026-10-25"
        XCTAssertFalse(DateUtils.isScheduled(entry, on: selectedDate), "An expired end date must hide the class.")

        entry.endDate = ""
        entry.isActive = false
        XCTAssertFalse(DateUtils.isScheduled(entry, on: selectedDate), "Inactive entries must not appear as scheduled.")

        entry.isActive = true
        entry.dayOfWeek = entry.dayOfWeek % 7 + 1
        XCTAssertFalse(DateUtils.isScheduled(entry, on: selectedDate), "An entry for another weekday must not match.")
    }

    func testWeekdaySelectionResolvesWithinTheReferenceWeek() throws {
        let referenceDate = try makeDate("2026-10-28") // Wednesday
        let monday = DateUtils.date(forDayOfWeek: 1, inWeekContaining: referenceDate)
        let sunday = DateUtils.date(forDayOfWeek: 7, inWeekContaining: referenceDate)

        XCTAssertEqual(DateUtils.isoString(monday), "2026-10-26")
        XCTAssertEqual(DateUtils.isoString(sunday), "2026-11-01")
    }

    func testAndroidBackupFixtureImportsAndExportsCoreRelationships() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let fixtureURL = try XCTUnwrap(
            Bundle(for: type(of: self)).url(forResource: "android-backup", withExtension: "json")
        )
        let fixture = try Data(contentsOf: fixtureURL)

        let result = try BackupService.importData(fixture, into: context, replaceExisting: true)
        XCTAssertEqual(result.subjects, 1)
        XCTAssertEqual(result.entries, 1)
        XCTAssertEqual(result.sessions, 1)
        XCTAssertEqual(result.units, 2)
        XCTAssertEqual(result.holidays, 1)
        XCTAssertEqual(result.skipped, 0)

        let subject = try XCTUnwrap(context.fetch(FetchDescriptor<Subject>()).first)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<TimetableEntry>()).first)
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<AttendanceSession>()).first)
        let units = try context.fetch(FetchDescriptor<AttendanceUnit>())
        let holiday = try XCTUnwrap(context.fetch(FetchDescriptor<Holiday>()).first)

        XCTAssertEqual(subject.name, "Mathematics")
        XCTAssertEqual(subject.code, "MATH101")
        XCTAssertEqual(entry.subject?.id, subject.id)
        XCTAssertEqual(entry.startDate, "2026-01-12")
        XCTAssertEqual(entry.endDate, "2026-12-21")
        XCTAssertEqual(session.subject?.id, subject.id)
        XCTAssertEqual(session.timetableEntryID, entry.id)
        XCTAssertEqual(session.sessionDate, "2026-10-26")
        XCTAssertEqual(units.map(\.statusRaw).sorted(), ["ABSENT", "PRESENT"])
        XCTAssertEqual(holiday.date, "2026-12-25")
        XCTAssertEqual(holiday.title, "Winter holiday")

        let exported = try BackupService.exportData(from: context)
        let backup = try JSONDecoder().decode(BackupFile.self, from: exported)
        XCTAssertEqual(backup.subjects?.first?.name, "Mathematics")
        XCTAssertEqual(backup.timetableEntries?.first?.startDate, "2026-01-12")
        XCTAssertEqual(backup.timetableEntries?.first?.endDate, "2026-12-21")
        XCTAssertEqual(backup.sessions?.first?.timetableEntryId, backup.timetableEntries?.first?.id)
        XCTAssertEqual(backup.units?.compactMap(\.status).sorted(), ["ABSENT", "PRESENT"])
        XCTAssertEqual(backup.holidays?.first?.title, "Winter holiday")
    }

    func testMergingTheSameBackupTwiceDoesNotDuplicateData() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let fixtureURL = try XCTUnwrap(
            Bundle(for: type(of: self)).url(forResource: "android-backup", withExtension: "json")
        )
        let fixture = try Data(contentsOf: fixtureURL)

        _ = try BackupService.importData(fixture, into: context, replaceExisting: true)
        let second = try BackupService.importData(fixture, into: context, replaceExisting: false)

        XCTAssertEqual(second.subjects, 0)
        XCTAssertEqual(second.entries, 0)
        XCTAssertEqual(second.sessions, 0)
        XCTAssertEqual(second.units, 0)
        XCTAssertEqual(second.holidays, 0)
        XCTAssertGreaterThan(second.alreadyPresent, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Subject>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TimetableEntry>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AttendanceSession>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AttendanceUnit>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Holiday>()).count, 1)
    }

    // MARK: Timetable scanner

    func testScannerReadsCommonTimeFormats() {
        XCTAssertEqual(TimetableScanner.timeRange("9:00-10:00")?.0, "09:00")
        XCTAssertEqual(TimetableScanner.timeRange("9:00-10:00")?.1, "10:00")
        XCTAssertEqual(TimetableScanner.timeRange("2-4 pm")?.0, "14:00")
        XCTAssertEqual(TimetableScanner.timeRange("2-4 pm")?.1, "16:00")
        XCTAssertEqual(TimetableScanner.timeRange("11-1 pm")?.0, "11:00")
        XCTAssertEqual(TimetableScanner.timeRange("11-1 pm")?.1, "13:00")
        XCTAssertEqual(TimetableScanner.timeRange("11 am to 1 pm")?.1, "13:00")
        XCTAssertEqual(TimetableScanner.timeRange("09.00 – 10.00")?.0, "09:00")
        XCTAssertEqual(TimetableScanner.timeRange("4-6")?.0, "16:00")
        XCTAssertNil(TimetableScanner.timeRange("Anatomy"))
        XCTAssertEqual(TimetableScanner.dayIndex("Thurs"), 4)
        XCTAssertEqual(TimetableScanner.dayIndex("SUNDAY"), 7)
        XCTAssertNil(TimetableScanner.dayIndex("Monsoon"))
    }

    func testScannerReadsGridWithDaysDownTheSide() {
        func t(_ text: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> ScannedText {
            ScannedText(text: text, box: CGRect(x: x, y: y, width: w, height: h))
        }
        let slots = ["9:00-10:00", "10:00-11:00", "11-12", "2-4 pm"]
        var items = [t("Day", 0.02, 0.05, 0.1, 0.03)]
        for (i, slot) in slots.enumerated() {
            items.append(t(slot, 0.16 + CGFloat(i) * 0.2, 0.05, 0.18, 0.03))
        }
        items += [
            t("Monday", 0.02, 0.20, 0.12, 0.03),
            t("Tuesday", 0.02, 0.40, 0.12, 0.03),
            t("Anatomy", 0.18, 0.20, 0.12, 0.03),
            t("LH-1", 0.18, 0.24, 0.08, 0.02),
            t("Physiology", 0.38, 0.20, 0.14, 0.03),
            t("Surgery Lab", 0.56, 0.40, 0.34, 0.03),
            t("Lunch", 0.78, 0.20, 0.1, 0.03),
        ]

        let found = TimetableScanner.parse(items)
        XCTAssertEqual(found, [
            ScannedClass(day: 1, start: "09:00", end: "10:00", name: "Anatomy"),
            ScannedClass(day: 1, start: "10:00", end: "11:00", name: "Physiology"),
            ScannedClass(day: 2, start: "11:00", end: "16:00", name: "Surgery Lab"),
        ])
    }

    func testScannerReadsGridWithDaysAcrossTheTopAndMergesDoubleSlots() {
        func t(_ text: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> ScannedText {
            ScannedText(text: text, box: CGRect(x: x, y: y, width: w, height: h))
        }
        var items = [t("Time", 0.02, 0.02, 0.1, 0.03)]
        for (i, day) in ["Mon", "Tue", "Wed"].enumerated() {
            items.append(t(day, 0.2 + CGFloat(i) * 0.2, 0.02, 0.1, 0.03))
        }
        for (i, slot) in ["9.00-10.00", "10.00-11.00", "1.00-2.00"].enumerated() {
            items.append(t(slot, 0.02, 0.12 + CGFloat(i) * 0.1, 0.14, 0.03))
        }
        items += [
            t("VSR Lab", 0.2, 0.12, 0.12, 0.03),
            t("VSR Lab", 0.2, 0.22, 0.12, 0.03),
            t("VMD Theory", 0.4, 0.32, 0.15, 0.03),
            t("Pharmacology", 0.6, 0.12, 0.15, 0.03),
        ]

        let found = TimetableScanner.parse(items)
        XCTAssertEqual(found, [
            ScannedClass(day: 1, start: "09:00", end: "11:00", name: "VSR Lab"),
            ScannedClass(day: 2, start: "13:00", end: "14:00", name: "VMD Theory"),
            ScannedClass(day: 3, start: "09:00", end: "10:00", name: "Pharmacology"),
        ])
    }

    func testScannerReadsSingleLineList() {
        let items = [
            ScannedText(text: "Monday 9:00-10:00 Anatomy", box: CGRect(x: 0.1, y: 0.1, width: 0.6, height: 0.03)),
            ScannedText(text: "Friday 2-4 pm Surgery Lab", box: CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.03)),
        ]
        XCTAssertEqual(TimetableScanner.parse(items), [
            ScannedClass(day: 1, start: "09:00", end: "10:00", name: "Anatomy"),
            ScannedClass(day: 5, start: "14:00", end: "16:00", name: "Surgery Lab"),
        ])
    }

    // MARK: Widget snapshot

    func testWidgetSnapshotPicksTodaysClassesAndRespectsHolidays() throws {
        let monday = try XCTUnwrap(DateUtils.date(fromISO: "2026-10-26"))
        let item = WidgetSnapshot.ClassItem(
            weekday: 1, date: nil, startTime: "09:00", endTime: "10:00", name: "Anatomy",
            room: "", colorARGB: 0, startDate: "", endDate: ""
        )
        var snapshot = WidgetSnapshot(
            generatedAt: monday, userName: "Marshal", percentage: 80, target: 75, present: 8, conducted: 10,
            message: "", classes: [item], holidays: [:], skipped: []
        )
        XCTAssertEqual(snapshot.classes(on: monday).map(\.name), ["Anatomy"])

        snapshot.skipped = ["2026-10-26|09:00|Anatomy"]
        XCTAssertTrue(snapshot.classes(on: monday).isEmpty)

        snapshot.skipped = []
        snapshot.holidays = ["2026-10-26": "Diwali"]
        XCTAssertTrue(snapshot.classes(on: monday).isEmpty)
    }

    // MARK: Assignments

    func testAssignmentStatusCoversEveryCase() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-26T12:00:00Z"))
        let hour: TimeInterval = 3600
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))

        XCTAssertEqual(AssignmentStatus.of(due: now.addingTimeInterval(5 * hour), completedAt: nil, now: now, calendar: utc), .dueToday)
        XCTAssertEqual(AssignmentStatus.of(due: now.addingTimeInterval(30 * hour), completedAt: nil, now: now, calendar: utc), .dueSoon)
        XCTAssertEqual(AssignmentStatus.of(due: now.addingTimeInterval(5 * 24 * hour), completedAt: nil, now: now, calendar: utc), .upcoming)
        XCTAssertEqual(
            AssignmentStatus.of(due: now.addingTimeInterval(-2 * 24 * hour), completedAt: nil, now: now, calendar: utc),
            .overdue(by: 2 * 24 * hour)
        )
        XCTAssertEqual(
            AssignmentStatus.of(due: now, completedAt: now.addingTimeInterval(-hour), now: now, calendar: utc),
            .doneOnTime
        )
        XCTAssertEqual(
            AssignmentStatus.of(due: now, completedAt: now.addingTimeInterval(3 * hour), now: now, calendar: utc),
            .doneLate(by: 3 * hour)
        )
        XCTAssertEqual(AssignmentStatus.overdue(by: 2 * 24 * hour).label, "Overdue by 2 days")
        XCTAssertEqual(AssignmentStatus.doneLate(by: 3 * hour).label, "Done 3 hours late")
    }

    func testAssignmentsSurviveBackupRoundTripWithoutDuplicates() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let subject = Subject(name: "Surgery")
        context.insert(subject)
        let due = Date(timeIntervalSince1970: 1_793_000_000)
        let done = Assignment(title: "Case report", dueDate: due, subjectID: subject.id)
        done.completedAt = due.addingTimeInterval(-3600)
        context.insert(done)
        context.insert(Assignment(title: "Reading log", dueDate: due.addingTimeInterval(86_400)))
        try context.save()

        let exported = try BackupService.exportData(from: context)

        let fresh = ModelContext(try makeContainer())
        let first = try BackupService.importData(exported, into: fresh, replaceExisting: true)
        XCTAssertEqual(first.assignments, 2)
        let restored = try fresh.fetch(FetchDescriptor<Assignment>(sortBy: [SortDescriptor(\.dueDate)]))
        XCTAssertEqual(restored.map(\.title), ["Case report", "Reading log"])
        let restoredSubject = try XCTUnwrap(fresh.fetch(FetchDescriptor<Subject>()).first)
        XCTAssertEqual(restored.first?.subjectID, restoredSubject.id)
        XCTAssertEqual(restored.first?.status(now: due), .doneOnTime)
        XCTAssertNil(restored.last?.completedAt)

        let second = try BackupService.importData(exported, into: fresh, replaceExisting: false)
        XCTAssertEqual(second.assignments, 0)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<Assignment>()).count, 2)
    }

    func testInvalidBackupIsRejected() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        XCTAssertThrowsError(
            try BackupService.importData(Data("not an AttendSmartly backup".utf8), into: context, replaceExisting: false)
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Subject.self,
            TimetableEntry.self,
            AttendanceSession.self,
            AttendanceUnit.self,
            Holiday.self,
            Assignment.self
        ])
        let configuration = ModelConfiguration(
            "AttendSmartlyTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeDate(_ iso: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return try XCTUnwrap(formatter.date(from: iso))
    }
}
