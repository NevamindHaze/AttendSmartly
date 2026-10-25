import SwiftUI
import SwiftData

struct TodayClass: Identifiable {
    let id: String
    let subject: Subject
    let entry: TimetableEntry?
    let session: AttendanceSession?
    let start: String
    let end: String
    let room: String
    let expectedUnits: Int
}

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [TimetableEntry]
    @Query private var sessions: [AttendanceSession]
    @Query private var holidays: [Holiday]
    @Query private var subjects: [Subject]

    @AppStorage(PrefKey.semesterEnabled) private var semesterEnabled = false
    @AppStorage(PrefKey.semesterStart) private var semesterStart = ""
    @AppStorage(PrefKey.semesterEnd) private var semesterEnd = ""

    @State private var showSettings = false
    @State private var showExtra = false
    @State private var rescheduleRow: TodayClass?
    @State private var errorText: String?

    private var semester: SemesterRange {
        SemesterRange(enabled: semesterEnabled, start: semesterStart, end: semesterEnd)
    }

    var body: some View {
        let todayStr = DateUtils.isoString(Date())
        let holiday = holidays.first { $0.date == todayStr }
        let rows = holiday == nil ? todayRows(todayStr) : []
        let summary = overallSummary()

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label(DateUtils.longDate(Date()), systemImage: "calendar")
                        .foregroundStyle(.secondary)

                    OverallCard(summary: summary, semesterOn: semesterEnabled)

                    HStack {
                        Text("Today's classes").font(.title2.bold())
                        Spacer()
                        Text("\(rows.count) scheduled").foregroundStyle(.secondary)
                    }

                    if let holiday {
                        infoBox(symbol: "party.popper", title: holiday.title, text: "No classes today.")
                    } else if rows.isEmpty {
                        infoBox(
                            symbol: "tray",
                            title: "No classes today",
                            text: subjects.isEmpty
                                ? "Add subjects, or import your Android backup from Settings (gear icon)."
                                : "Nothing is scheduled for today. Tap + to add an extra class."
                        )
                    } else {
                        ForEach(rows) { row in
                            ClassCard(
                                row: row,
                                statusFor: { index in unitStatus(row, index) },
                                onSet: { index, status in apply(row, [index: status], today: todayStr) },
                                onCancel: {
                                    var all: [Int: AttendanceStatus] = [:]
                                    for i in 0..<row.expectedUnits { all[i] = .cancelled }
                                    apply(row, all, today: todayStr)
                                },
                                onReschedule: { rescheduleRow = row }
                            )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("AttendSmartly")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showExtra = true } label: { Image(systemName: "plus.circle") }
                        .accessibilityLabel("Add extra class")
                        .disabled(subjects.filter { !$0.isArchived }.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showExtra) { AddExtraClassView() }
            .sheet(item: $rescheduleRow) { row in
                RescheduleView(row: row) { newDate, start, end in
                    reschedule(row, to: newDate, start: start, end: end, today: todayStr)
                }
            }
            .alert("Couldn't save", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    // MARK: Data

    private func todayRows(_ todayStr: String) -> [TodayClass] {
        let dow = DateUtils.dayOfWeek(Date())
        var rows: [TodayClass] = []
        var usedSessions = Set<UUID>()

        for e in entries where e.isActive && e.dayOfWeek == dow {
            guard let subject = e.subject, !subject.isArchived else { continue }
            if !e.startDate.isEmpty && e.startDate > todayStr { continue }
            if !e.endDate.isEmpty && e.endDate < todayStr { continue }
            let session = sessions.first { $0.sessionDate == todayStr && $0.timetableEntryID == e.id }
            if let session { usedSessions.insert(session.id) }
            rows.append(TodayClass(
                id: e.id.uuidString,
                subject: subject,
                entry: e,
                session: session,
                start: session?.startTime ?? e.startTime,
                end: session?.endTime ?? e.endTime,
                room: e.roomOverride.isEmpty ? subject.room : e.roomOverride,
                expectedUnits: max(1, session?.expectedUnitCount ?? e.attendanceUnitCount)
            ))
        }

        // Extra / rescheduled classes recorded for today
        for s in sessions where s.sessionDate == todayStr && !usedSessions.contains(s.id) {
            guard let subject = s.subject, !subject.isArchived else { continue }
            rows.append(TodayClass(
                id: s.id.uuidString,
                subject: subject,
                entry: nil,
                session: s,
                start: s.startTime,
                end: s.endTime,
                room: subject.room,
                expectedUnits: max(1, s.expectedUnitCount)
            ))
        }

        return rows.sorted { $0.start < $1.start }
    }

    private func unitStatus(_ row: TodayClass, _ index: Int) -> AttendanceStatus {
        row.session?.units.first(where: { $0.unitIndex == index })?.status ?? .unmarked
    }

    /// Finds today's session for a row, or creates it once.
    private func ensureSession(for row: TodayClass, on dateISO: String) -> AttendanceSession {
        if let existing = row.session { return existing }
        let created = AttendanceSession(
            sessionDate: dateISO, startTime: row.start, endTime: row.end,
            expectedUnitCount: row.expectedUnits
        )
        created.timetableEntryID = row.entry?.id
        context.insert(created)
        created.subject = row.subject
        return created
    }

    private func setUnits(_ session: AttendanceSession, _ changes: [Int: AttendanceStatus]) {
        for (index, status) in changes {
            if let unit = session.units.first(where: { $0.unitIndex == index }) {
                unit.status = status
                unit.markedAt = Date()
            } else {
                let unit = AttendanceUnit(unitIndex: index, status: status)
                context.insert(unit)
                unit.session = session
            }
        }
    }

    private func apply(_ row: TodayClass, _ changes: [Int: AttendanceStatus], today: String) {
        let session = ensureSession(for: row, on: today)
        setUnits(session, changes)
        save()
    }

    private func reschedule(_ row: TodayClass, to newDate: Date, start: String, end: String, today: String) {
        let newISO = DateUtils.isoString(newDate)

        let original = ensureSession(for: row, on: today)
        var cancelled: [Int: AttendanceStatus] = [:]
        for i in 0..<row.expectedUnits { cancelled[i] = .cancelled }
        setUnits(original, cancelled)
        original.isRescheduled = true
        original.notes = "Rescheduled to \(newISO)"

        let moved = AttendanceSession(
            sessionDate: newISO, startTime: start, endTime: end,
            expectedUnitCount: row.expectedUnits
        )
        moved.isRescheduled = true
        moved.notes = "Rescheduled from \(today)"
        context.insert(moved)
        moved.subject = row.subject

        save()
    }

    private func save() {
        do { try context.save() } catch { errorText = error.localizedDescription }
    }

    private func overallSummary() -> AttendanceSummary {
        let active = subjects.filter { !$0.isArchived }
        let statuses = sessions
            .filter { semester.includes($0.sessionDate) }
            .flatMap { s -> [AttendanceStatus] in
                guard let subject = s.subject, !subject.isArchived else { return [] }
                return s.units.map { $0.status }
            }
        let target = active.isEmpty ? 75 : active.map { $0.targetPercentage }.reduce(0, +) / Double(active.count)
        return AttendanceCalculator.summary(statuses: statuses, target: target)
    }

    private func infoBox(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title).foregroundStyle(DashboardPalette.green)
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct OverallCard: View {
    let summary: AttendanceSummary
    let semesterOn: Bool

    var body: some View {
        let onTrack = summary.conducted == 0 || summary.percentage >= summary.target
        let tint = onTrack ? DashboardPalette.green : DashboardPalette.coral

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Overall attendance").font(.headline)
                    Text(semesterOn ? "This semester" : "Across all subjects")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text(summary.conducted == 0 ? "No data" : (onTrack ? "On track" : "Below target"))
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(tint)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(summary.percentage.rounded()))%")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                Text("attendance").foregroundStyle(.secondary)
            }

            ProgressView(value: min(summary.percentage, 100), total: 100).tint(tint)

            HStack {
                VStack(alignment: .leading) {
                    Text("\(summary.present)").font(.title2.bold())
                    Text("Attended").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(summary.conducted)").font(.title2.bold())
                    Text("Total classes").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct ClassCard: View {
    let row: TodayClass
    let statusFor: (Int) -> AttendanceStatus
    let onSet: (Int, AttendanceStatus) -> Void
    let onCancel: () -> Void
    let onReschedule: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(argb: row.subject.colorValue))
                .frame(width: 5)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(row.subject.name).font(.headline)
                    Spacer()
                    if !row.subject.code.isEmpty {
                        Text(row.subject.code).font(.caption).foregroundStyle(.secondary)
                    }
                    Menu {
                        Button("Cancel class", systemImage: "xmark.circle", role: .destructive, action: onCancel)
                        Button("Reschedule…", systemImage: "calendar.badge.clock", action: onReschedule)
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                    }
                }
                Text("\(DateUtils.displayTime(row.start)) – \(DateUtils.displayTime(row.end))"
                     + (row.room.isEmpty ? "" : "  ·  \(row.room)"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(0..<row.expectedUnits, id: \.self) { index in
                    HStack(spacing: 8) {
                        if row.expectedUnits > 1 {
                            Text("Unit \(index + 1)").font(.caption).foregroundStyle(.secondary)
                        }
                        chip("Present", .present, index, DashboardPalette.green)
                        chip("Absent", .absent, index, DashboardPalette.coral)
                        chip("Cancelled", .cancelled, index, .gray)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func chip(_ title: String, _ status: AttendanceStatus, _ index: Int, _ tint: Color) -> some View {
        let selected = statusFor(index) == status
        return Button {
            onSet(index, selected ? .unmarked : status)
        } label: {
            Text(title)
                .font(.caption.bold())
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(selected ? tint : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
