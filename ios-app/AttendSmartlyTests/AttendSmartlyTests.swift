import XCTest
import SwiftData
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
            Holiday.self
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
