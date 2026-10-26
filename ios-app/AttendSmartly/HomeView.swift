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
    @State private var showCalendarPicker = false
    @State private var calendarPickerDate = Date()
    @State private var selectedDate = Date()
    @State private var rescheduleRow: TodayClass?
    @State private var errorText: String?

    private var semester: SemesterRange {
        SemesterRange(enabled: semesterEnabled, start: semesterStart, end: semesterEnd)
    }

    var body: some View {
        let todayStr = DateUtils.isoString(selectedDate)
        let selectedIsToday = Calendar.current.isDateInToday(selectedDate)
        let holiday = holidays.first { $0.date == todayStr }
        let rows = holiday == nil ? scheduleRows(on: selectedDate) : []
        let summary = overallSummary()

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Label(DateUtils.longDate(selectedDate), systemImage: "calendar")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !selectedIsToday {
                            Button("Today") {
                                selectedDate = Calendar.current.startOfDay(for: Date())
                            }
                            .font(.caption.bold())
                            .accessibilityLabel("Return to today")
                        }
                    }

                    HeroCard(summary: summary, semesterOn: semesterEnabled)

                    HStack {
                        Text(selectedIsToday ? "Today" : "Classes").font(.title2.bold())
                        Spacer()
                        Text(rows.count == 1 ? "1 class" : "\(rows.count) classes")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let holiday {
                        infoBox(
                            symbol: "party.popper",
                            title: holiday.title,
                            text: selectedIsToday ? "No classes today." : "No classes on this date."
                        )
                    } else if rows.isEmpty {
                        infoBox(
                            symbol: "tray",
                            title: selectedIsToday ? "No classes today" : "No classes on this date",
                            text: subjects.isEmpty
                                ? "Add subjects, or import your Android backup from Settings (gear icon)."
                                : (selectedIsToday
                                   ? "Nothing is scheduled for today. Tap + to add an extra class."
                                   : "Nothing is scheduled for this date. Tap + to add an extra class.")
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
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("AttendSmartly")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showExtra = true } label: { Image(systemName: "plus.circle") }
                        .accessibilityLabel("Add extra class")
                        .disabled(subjects.filter { !$0.isArchived }.isEmpty)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        calendarPickerDate = selectedDate
                        showCalendarPicker = true
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Choose attendance date")

                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showCalendarPicker) {
                NavigationStack {
                    VStack(spacing: 12) {
                        DatePicker(
                            "Attendance date",
                            selection: $calendarPickerDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()

                        Text("Choose a past or future day to review or mark attendance.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .navigationTitle("Choose a date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showCalendarPicker = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                selectedDate = Calendar.current.startOfDay(for: calendarPickerDate)
                                showCalendarPicker = false
                            }
                        }
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showExtra) { AddExtraClassView(initialDate: selectedDate) }
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

    private func scheduleRows(on date: Date) -> [TodayClass] {
        let todayStr = DateUtils.isoString(date)
        var rows: [TodayClass] = []
        var usedSessions = Set<UUID>()

        for e in entries where DateUtils.isScheduled(e, on: date) {
            guard let subject = e.subject, !subject.isArchived else { continue }
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

        // Extra / rescheduled classes recorded for this date
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
        EmptyStateView(symbol: symbol, title: title, message: text)
            .cardStyle(20)
    }
}

private struct HeroCard: View {
    let summary: AttendanceSummary
    let semesterOn: Bool

    var body: some View {
        let tint = attendanceTint(summary)
        let hasData = summary.conducted > 0

        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 22) {
                ProgressRing(
                    value: hasData ? summary.percentage : 0,
                    target: hasData ? summary.target : nil,
                    tint: tint,
                    lineWidth: 14
                ) {
                    VStack(spacing: 0) {
                        Text(hasData ? "\(Int(summary.percentage.rounded()))%" : "–")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: summary.percentage)
                        Text("goal \(Int(summary.target.rounded()))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 148, height: 148)

                VStack(alignment: .leading, spacing: 10) {
                    StatusPill(text: attendanceLabel(summary), tint: tint)
                    stat("Present", summary.present, DashboardPalette.green)
                    stat("Absent", summary.absent, DashboardPalette.coral)
                    stat("Cancelled", summary.cancelled, DashboardPalette.blue)
                }
            }

            Text(summary.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(semesterOn ? "Counting this semester only" : "Counting all recorded classes")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(26)
    }

    private func stat(_ title: String, _ value: Int, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text("\(value)")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ClassCard: View {
    let row: TodayClass
    let statusFor: (Int) -> AttendanceStatus
    let onSet: (Int, AttendanceStatus) -> Void
    let onCancel: () -> Void
    let onReschedule: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(DateUtils.displayTime(row.start))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text(DateUtils.displayTime(row.end))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 68, alignment: .trailing)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(argb: row.subject.colorValue))
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(row.subject.name).font(.headline)
                    let detail = [row.subject.code, row.room].filter { !$0.isEmpty }.joined(separator: "  ")
                    if !detail.isEmpty {
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Menu {
                    Button("Reschedule…", systemImage: "calendar.badge.clock", action: onReschedule)
                    Button("Cancel class", systemImage: "xmark.circle", role: .destructive, action: onCancel)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
            }

            VStack(spacing: 8) {
                ForEach(0..<row.expectedUnits, id: \.self) { index in
                    HStack(spacing: 8) {
                        if row.expectedUnits > 1 {
                            Text("Unit \(index + 1)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .leading)
                        }
                        choice("Present", "checkmark", .present, index, DashboardPalette.green)
                        choice("Absent", "xmark", .absent, index, DashboardPalette.coral)
                        choice("Cancelled", "slash.circle", .cancelled, index, DashboardPalette.blue)
                    }
                }
            }
        }
        .padding(16)
        .cardStyle(20)
    }

    private func choice(_ title: String, _ symbol: String, _ status: AttendanceStatus, _ index: Int, _ tint: Color) -> some View {
        let selected = statusFor(index) == status
        return Button {
            onSet(index, selected ? .unmarked : status)
        } label: {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    selected ? tint : tint.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .foregroundStyle(selected ? Color.white : tint)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: selected)
        .sensoryFeedback(.selection, trigger: selected)
    }
}
