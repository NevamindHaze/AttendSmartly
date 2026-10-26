import SwiftUI
import SwiftData

struct TimetableView: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [TimetableEntry]
    @Query private var subjects: [Subject]

    @State private var day: Int = DateUtils.dayOfWeek(Date())
    @State private var showAllEntries = false
    @State private var formEntry: TimetableEntry?
    @State private var showForm = false
    @State private var showScan = false
    @State private var errorText: String?

    private static let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        let selectedDate = DateUtils.date(forDayOfWeek: day, inWeekContaining: Date())
        let selectedDateISO = DateUtils.isoString(selectedDate)
        let allDayEntries = entries.filter { $0.dayOfWeek == day && $0.subject != nil }
        let dayEntries = allDayEntries
            .filter { showAllEntries || DateUtils.isScheduled($0, on: selectedDate) }
            .sorted { $0.startTime < $1.startTime }

        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    DayStrip(day: $day)
                    HStack {
                        Text(DateUtils.prettyDate(selectedDateISO))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle(isOn: $showAllEntries) {
                            Text("Show all")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .toggleStyle(.switch)
                        .fixedSize()
                        .accessibilityHint("Also shows inactive classes and classes outside their date range")
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                if dayEntries.isEmpty {
                    EmptyStateView(
                        symbol: "calendar",
                        title: showAllEntries || allDayEntries.isEmpty
                            ? "No classes on this day"
                            : "No active classes on this date",
                        message: subjects.isEmpty
                            ? "Add a subject first, then schedule it here."
                            : (!showAllEntries && !allDayEntries.isEmpty
                               ? "Turn on Show all to see inactive or out-of-range classes."
                               : "Tap + to schedule a class.")
                    )
                    .tile(Pastel.surface)
                    .padding()
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    List {
                        ForEach(dayEntries) { entry in
                            Button {
                                formEntry = entry
                                showForm = true
                            } label: {
                                EntryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .pastelRow(Pastel.subject(entry.subject?.colorValue ?? 0xFF607D8B))
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    context.delete(entry)
                                    save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Pastel.background)
            .navigationTitle("Timetable")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            formEntry = nil
                            showForm = true
                        } label: {
                            Label("Add a class", systemImage: "plus")
                        }
                        .disabled(subjects.filter { !$0.isArchived }.isEmpty)
                        Button {
                            showScan = true
                        } label: {
                            Label("Scan a timetable photo", systemImage: "text.viewfinder")
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showScan) { TimetableScanView() }
            .sheet(isPresented: $showForm, onDismiss: { formEntry = nil }) {
                TimetableFormView(entry: formEntry, defaultDay: day)
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

    private func save() {
        do { try context.save() } catch { errorText = error.localizedDescription }
    }
}

private struct EntryRow: View {
    let entry: TimetableEntry

    var body: some View {
        let subject = entry.subject
        let room = entry.roomOverride.isEmpty ? (subject?.room ?? "") : entry.roomOverride

        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DateUtils.displayTime(entry.startTime))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                Text(DateUtils.displayTime(entry.endTime))
                    .font(.caption)
                    .opacity(0.65)
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 68, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                Text(subject?.name ?? "Unknown")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                if !room.isEmpty {
                    Label(room, systemImage: "mappin.and.ellipse")
                        .font(.footnote)
                        .opacity(0.75)
                }
                HStack(spacing: 6) {
                    if entry.attendanceUnitCount > 1 {
                        TilePill(text: "\(entry.attendanceUnitCount) units")
                    }
                    if !entry.isActive {
                        TilePill(text: "Inactive", symbol: "pause.circle")
                    }
                    if !entry.startDate.isEmpty || !entry.endDate.isEmpty {
                        TilePill(text: "\(entry.startDate.isEmpty ? "…" : DateUtils.prettyDate(entry.startDate)) → \(entry.endDate.isEmpty ? "…" : DateUtils.prettyDate(entry.endDate))")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Pastel.ink)
        .contentShape(Rectangle())
    }
}

struct TimetableFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Subject.name) private var subjects: [Subject]

    let entry: TimetableEntry?

    @State private var subjectID: UUID?
    @State private var day: Int
    @State private var start: Date
    @State private var end: Date
    @State private var units: Int
    @State private var room: String
    @State private var teacher: String
    @State private var isActive: Bool
    @State private var hasStartDate: Bool
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var errorText: String?

    private static let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    init(entry: TimetableEntry?, defaultDay: Int) {
        self.entry = entry
        _subjectID = State(initialValue: entry?.subject?.id)
        _day = State(initialValue: entry?.dayOfWeek ?? defaultDay)
        _start = State(initialValue: DateUtils.time(from: entry?.startTime ?? "09:00"))
        _end = State(initialValue: DateUtils.time(from: entry?.endTime ?? "10:00"))
        _units = State(initialValue: entry?.attendanceUnitCount ?? 1)
        _room = State(initialValue: entry?.roomOverride ?? "")
        _teacher = State(initialValue: entry?.teacherOverride ?? "")
        _isActive = State(initialValue: entry?.isActive ?? true)
        let sd = entry.flatMap { DateUtils.date(fromISO: $0.startDate) }
        let ed = entry.flatMap { DateUtils.date(fromISO: $0.endDate) }
        _hasStartDate = State(initialValue: sd != nil)
        _startDate = State(initialValue: sd ?? Date())
        _hasEndDate = State(initialValue: ed != nil)
        _endDate = State(initialValue: ed ?? Date())
    }

    private var selectableSubjects: [Subject] {
        subjects.filter { !$0.isArchived || $0.id == entry?.subject?.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Class") {
                    Picker("Subject", selection: $subjectID) {
                        Text("Select…").tag(UUID?.none)
                        ForEach(selectableSubjects) { s in
                            Text(s.name).tag(Optional(s.id))
                        }
                    }
                    Picker("Day", selection: $day) {
                        ForEach(1...7, id: \.self) { d in
                            Text(Self.dayNames[d - 1]).tag(d)
                        }
                    }
                    DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
                    Stepper("Attendance units: \(units)", value: $units, in: 1...6)
                }

                Section("Overrides (optional)") {
                    TextField("Room", text: $room)
                    TextField("Teacher", text: $teacher)
                }

                Section("Active period") {
                    Toggle("Active", isOn: $isActive)
                    Toggle("Starts on a date", isOn: $hasStartDate)
                    if hasStartDate {
                        DatePicker("From", selection: $startDate, displayedComponents: .date)
                    }
                    Toggle("Ends on a date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("Until", selection: $endDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle(entry == nil ? "New Class" : "Edit Class")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(subjectID == nil)
                }
            }
            .onChange(of: subjectID) { _, newValue in
                if entry == nil, let s = subjects.first(where: { $0.id == newValue }) {
                    units = s.defaultAttendanceUnits
                }
            }
            .alert("Check the class", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    private func save() {
        guard let subject = subjects.first(where: { $0.id == subjectID }) else {
            errorText = "Pick a subject."
            return
        }
        let startStr = DateUtils.hhmm(start)
        let endStr = DateUtils.hhmm(end)
        guard endStr > startStr else {
            errorText = "The end time must be after the start time."
            return
        }
        if hasStartDate && hasEndDate && DateUtils.isoString(endDate) < DateUtils.isoString(startDate) {
            errorText = "The end date must not be before the start date."
            return
        }

        let e = entry ?? TimetableEntry()
        if entry == nil { context.insert(e) }
        e.subject = subject
        e.dayOfWeek = day
        e.startTime = startStr
        e.endTime = endStr
        e.attendanceUnitCount = units
        e.roomOverride = room.trimmingCharacters(in: .whitespacesAndNewlines)
        e.teacherOverride = teacher.trimmingCharacters(in: .whitespacesAndNewlines)
        e.isActive = isActive
        e.startDate = hasStartDate ? DateUtils.isoString(startDate) : ""
        e.endDate = hasEndDate ? DateUtils.isoString(endDate) : ""
        do {
            try context.save()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
