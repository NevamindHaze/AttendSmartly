import SwiftUI
import SwiftData

struct AttendanceDayClass: Identifiable {
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

    @State private var showSettings = false
    @State private var showCalendarPicker = false
    @State private var calendarPickerDate = Date()
    @State private var selectedDate = Date()
    @State private var errorText: String?

    var body: some View {
        let selectedDateISO = DateUtils.isoString(selectedDate)
        let selectedDateIsToday = Calendar.current.isDateInToday(selectedDate)
        let holiday = holidays.first { $0.date == selectedDateISO }
        let rows = holiday == nil ? scheduleRows(on: selectedDate) : []
        let summary = overallSummary()

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Label(DateUtils.longDate(selectedDate), systemImage: "calendar")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !selectedDateIsToday {
                            Button("Today") {
                                selectedDate = Calendar.current.startOfDay(for: Date())
                            }
                            .font(.caption.bold())
                            .accessibilityLabel("Return to today")
                        }
                    }

                    OverallCard(summary: summary)

                    HStack {
                        Text(selectedDateIsToday ? "Today's classes" : "Classes")
                            .font(.title2.bold())
                        Spacer()
                        Text("\(rows.count) scheduled").foregroundStyle(.secondary)
                    }

                    if let holiday {
                        infoBox(
                            symbol: "party.popper",
                            title: holiday.title,
                            text: selectedDateIsToday ? "No classes today." : "No classes on this date."
                        )
                    } else if rows.isEmpty {
                        infoBox(
                            symbol: "tray",
                            title: selectedDateIsToday ? "No classes today" : "No classes on this date",
                            text: subjects.isEmpty
                                ? "Add subjects, or import your Android backup from Settings (gear icon)."
                                : (selectedDateIsToday ? "Nothing is scheduled for today." : "Nothing is scheduled for this date.")
                        )
                    } else {
                        ForEach(rows) { row in
                            ClassCard(
                                row: row,
                                statusFor: { index in unitStatus(row, index) },
                                onSet: { index, status in setStatus(row, unit: index, to: status, today: selectedDateISO) }
                            )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("AttendSmartly")
            .toolbar {
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

    private func scheduleRows(on date: Date) -> [AttendanceDayClass] {
        let dateISO = DateUtils.isoString(date)
        var rows: [AttendanceDayClass] = []
        var usedSessions = Set<UUID>()

        for e in entries where DateUtils.isScheduled(e, on: date) {
            guard let subject = e.subject, !subject.isArchived else { continue }
            let session = sessions.first { $0.sessionDate == dateISO && $0.timetableEntryID == e.id }
            if let session { usedSessions.insert(session.id) }
            rows.append(AttendanceDayClass(
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

        // Extra / one-off classes recorded for this date
        for s in sessions where s.sessionDate == dateISO && !usedSessions.contains(s.id) {
            guard let subject = s.subject, !subject.isArchived else { continue }
            rows.append(AttendanceDayClass(
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

    private func unitStatus(_ row: AttendanceDayClass, _ index: Int) -> AttendanceStatus {
        row.session?.units.first(where: { $0.unitIndex == index })?.status ?? .unmarked
    }

    private func setStatus(_ row: AttendanceDayClass, unit index: Int, to status: AttendanceStatus, today: String) {
        let session: AttendanceSession
        if let existing = row.session {
            session = existing
        } else {
            let created = AttendanceSession(
                sessionDate: today, startTime: row.start, endTime: row.end,
                expectedUnitCount: row.expectedUnits
            )
            created.timetableEntryID = row.entry?.id
            context.insert(created)
            created.subject = row.subject
            session = created
        }

        if let unit = session.units.first(where: { $0.unitIndex == index }) {
            unit.status = status
            unit.markedAt = Date()
        } else {
            let unit = AttendanceUnit(unitIndex: index, status: status)
            context.insert(unit)
            unit.session = session
        }

        do { try context.save() } catch { errorText = error.localizedDescription }
    }

    private func overallSummary() -> AttendanceSummary {
        let active = subjects.filter { !$0.isArchived }
        let statuses = sessions.flatMap { s -> [AttendanceStatus] in
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

    var body: some View {
        let onTrack = summary.conducted == 0 || summary.percentage >= summary.target
        let tint = onTrack ? DashboardPalette.green : DashboardPalette.coral

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Overall attendance").font(.headline)
                    Text("Across all subjects").font(.subheadline).foregroundStyle(.secondary)
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
    let row: AttendanceDayClass
    let statusFor: (Int) -> AttendanceStatus
    let onSet: (Int, AttendanceStatus) -> Void

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
