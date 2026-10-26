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
    @AppStorage(PrefKey.userName) private var userName = "Marshal"

    private var displayName: String {
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "there" : name
    }

    private var semester: SemesterRange {
        SemesterRange(enabled: semesterEnabled, start: semesterStart, end: semesterEnd)
    }

    var body: some View {
        let todayStr = DateUtils.isoString(selectedDate)
        let selectedIsToday = Calendar.current.isDateInToday(selectedDate)
        let holiday = holidays.first { $0.date == todayStr }
        let rows = holiday == nil ? scheduleRows(on: selectedDate) : []
        let summary = overallSummary()
        let dayWord = selectedIsToday ? "today" : "this day"
        let classCountLabel = (rows.count == 1 ? "class\n" : "classes\n") + dayWord

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Button { showSettings = true } label: { AvatarView(size: 50) }
                            .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hi, \(displayName)")
                                .font(.system(.title2, design: .rounded).weight(.bold))
                                .foregroundStyle(Pastel.ink)
                            Text(DateUtils.longDate(selectedDate))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if !selectedIsToday {
                            Button("Today") {
                                selectedDate = Calendar.current.startOfDay(for: Date())
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Pastel.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Pastel.surface, in: Capsule())
                            .accessibilityLabel("Return to today")
                        }
                    }

                    HeroCard(summary: summary, semesterOn: semesterEnabled)

                    HStack(spacing: 12) {
                        if summary.conducted > 0 && summary.percentage < summary.target && summary.requiredUnits != Int.max {
                            QuickTile(value: "\(summary.requiredUnits)", label: "classes to attend\nto reach your goal",
                                      symbol: "arrow.up.right", color: Pastel.peach)
                        } else {
                            QuickTile(value: "\(summary.safeBunks)", label: "classes you can\nsafely miss",
                                      symbol: "cup.and.saucer.fill", color: Pastel.sky)
                        }
                        QuickTile(value: "\(rows.count)", label: classCountLabel,
                                  symbol: "book.fill", color: Pastel.lavender)
                    }

                    Text(selectedIsToday ? "Today's classes" : "Classes")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Pastel.ink)
                        .padding(.top, 4)

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
            .background(Pastel.background)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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
            .tile(Pastel.surface)
    }
}

private struct QuickTile: View {
    let value: String
    let label: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Pastel.ink)
                .frame(width: 34, height: 34)
                .background(Pastel.surface.opacity(0.75), in: Circle())
            Text(value)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Pastel.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Pastel.ink.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile(color, radius: 26)
    }
}

private struct HeroCard: View {
    let summary: AttendanceSummary
    let semesterOn: Bool

    var body: some View {
        let hasData = summary.conducted > 0
        let progress = hasData ? min(max(summary.percentage, 0), 100) / 100 : 0
        let goal = min(max(summary.target, 0), 100) / 100

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(semesterOn ? "This semester" : "Overall attendance")
                    .font(.headline)
                    .foregroundStyle(Pastel.ink)
                Spacer()
                TilePill(text: attendanceLabel(summary))
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(hasData ? "\(Int(summary.percentage.rounded()))%" : "–")
                    .font(.system(size: 68, weight: .heavy, design: .rounded))
                    .foregroundStyle(Pastel.ink)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: summary.percentage)
                Text("goal \(Int(summary.target.rounded()))%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Pastel.ink.opacity(0.6))
            }

            // Chunky progress bar with a marker at the goal.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Pastel.ink.opacity(0.12))
                    Capsule()
                        .fill(Pastel.ink)
                        .frame(width: max(14, geo.size.width * progress))
                        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: progress)
                    Capsule()
                        .fill(Pastel.surface)
                        .frame(width: 4, height: 22)
                        .overlay(Capsule().strokeBorder(Pastel.ink.opacity(0.5), lineWidth: 1))
                        .offset(x: geo.size.width * goal - 2)
                }
            }
            .frame(height: 14)

            HStack(spacing: 8) {
                countChip(summary.present, "present", "checkmark")
                countChip(summary.absent, "absent", "xmark")
                countChip(summary.cancelled, "cancelled", "slash.circle")
            }

            Text(summary.message)
                .font(.subheadline)
                .foregroundStyle(Pastel.ink.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile(Pastel.status(summary), radius: 32)
    }

    private func countChip(_ value: Int, _ title: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .opacity(0.7)
        }
        .foregroundStyle(Pastel.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Pastel.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            HStack {
                TilePill(
                    text: "\(DateUtils.displayTime(row.start)) – \(DateUtils.displayTime(row.end))",
                    symbol: "clock"
                )
                Spacer()
                Menu {
                    Button("Reschedule…", systemImage: "calendar.badge.clock", action: onReschedule)
                    Button("Cancel class", systemImage: "xmark.circle", role: .destructive, action: onCancel)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Pastel.ink)
                        .frame(width: 34, height: 34)
                        .background(Pastel.surface.opacity(0.75), in: Circle())
                }
                .accessibilityLabel("Class options")
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(row.subject.name)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Pastel.ink)
                let detail = [row.subject.code, row.room].filter { !$0.isEmpty }.joined(separator: "  ")
                if !detail.isEmpty {
                    Label(detail, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(Pastel.ink.opacity(0.7))
                }
            }

            VStack(spacing: 8) {
                ForEach(0..<row.expectedUnits, id: \.self) { index in
                    HStack(spacing: 8) {
                        if row.expectedUnits > 1 {
                            Text("Unit \(index + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Pastel.ink.opacity(0.7))
                                .frame(width: 42, alignment: .leading)
                        }
                        choice("Present", "checkmark", .present, index, DashboardPalette.green)
                        choice("Absent", "xmark", .absent, index, DashboardPalette.coral)
                        choice("Cancelled", "slash.circle", .cancelled, index, DashboardPalette.blue)
                    }
                }
            }
        }
        .padding(18)
        .tile(Pastel.subject(row.subject.colorValue), radius: 28)
    }

    private func choice(_ title: String, _ symbol: String, _ status: AttendanceStatus, _ index: Int, _ tint: Color) -> some View {
        let selected = statusFor(index) == status
        return Button {
            onSet(index, selected ? .unmarked : status)
        } label: {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(selected ? tint : Pastel.surface.opacity(0.75), in: Capsule())
                .foregroundStyle(selected ? Color.white : Pastel.ink)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: selected)
        .sensoryFeedback(.selection, trigger: selected)
    }
}
