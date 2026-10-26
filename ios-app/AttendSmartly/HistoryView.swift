import SwiftUI
import SwiftData

extension AttendanceStatus {
    var label: String {
        switch self {
        case .unmarked: return "Unmarked"
        case .present: return "Present"
        case .absent: return "Absent"
        case .bunked: return "Bunked"
        case .cancelled: return "Cancelled"
        }
    }

    var tint: Color {
        switch self {
        case .unmarked: return .gray
        case .present: return DashboardPalette.green
        case .absent: return DashboardPalette.coral
        case .bunked: return .orange
        case .cancelled: return DashboardPalette.blue
        }
    }
}

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AttendanceSession.sessionDate, order: .reverse) private var sessions: [AttendanceSession]
    @Query(sort: \Subject.name) private var subjects: [Subject]

    @State private var filterID: UUID?
    @State private var editing: AttendanceSession?
    @State private var showAdd = false
    @State private var toDelete: AttendanceSession?
    @State private var errorText: String?

    var body: some View {
        let filtered = sessions.filter { s in
            s.subject != nil && (filterID == nil || s.subject?.id == filterID)
        }
        let grouped = Dictionary(grouping: filtered, by: { $0.sessionDate })
        let dates = grouped.keys.sorted(by: >)

        NavigationStack {
            Group {
                if dates.isEmpty {
                    EmptyStateView(
                        symbol: "clock.arrow.circlepath",
                        title: "No records yet",
                        message: "Mark classes on Home, or tap + to add a past class."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(dates, id: \.self) { date in
                            Section(DateUtils.prettyDate(date)) {
                                ForEach((grouped[date] ?? []).sorted { $0.startTime < $1.startTime }) { session in
                                    Button { editing = session } label: { SessionRow(session: session) }
                                        .buttonStyle(.plain)
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) { toDelete = session } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("All subjects") { filterID = nil }
                        ForEach(subjects) { s in
                            Button(s.name) { filterID = s.id }
                        }
                    } label: {
                        Label("Filter", systemImage: filterID == nil
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Label("Add past class", systemImage: "plus") }
                        .disabled(subjects.filter { !$0.isArchived }.isEmpty)
                }
            }
            .sheet(item: $editing) { session in
                SessionEditView(session: session)
            }
            .sheet(isPresented: $showAdd) { AddPastClassView() }
            .alert("Delete this record?", isPresented: Binding(
                get: { toDelete != nil },
                set: { if !$0 { toDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let s = toDelete {
                        context.delete(s)
                        do { try context.save() } catch { errorText = error.localizedDescription }
                    }
                    toDelete = nil
                }
                Button("Cancel", role: .cancel) { toDelete = nil }
            } message: {
                Text("This removes the class and its attendance marks.")
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
}

private struct SessionRow: View {
    let session: AttendanceSession

    var body: some View {
        let count = max(session.expectedUnitCount, session.units.count)
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(argb: session.subject?.colorValue ?? 0xFF607D8B))
                .frame(width: 5, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.subject?.name ?? "Unknown").font(.headline)
                Text("\(DateUtils.displayTime(session.startTime)) – \(DateUtils.displayTime(session.endTime))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                ForEach(0..<count, id: \.self) { index in
                    let status = session.units.first(where: { $0.unitIndex == index })?.status ?? .unmarked
                    Text(status.label)
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(status.tint.opacity(0.18), in: Capsule())
                        .foregroundStyle(status.tint)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

struct SessionEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let session: AttendanceSession
    @State private var errorText: String?

    var body: some View {
        let count = max(session.expectedUnitCount, session.units.count)
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Subject", value: session.subject?.name ?? "Unknown")
                    LabeledContent("Date", value: DateUtils.prettyDate(session.sessionDate))
                    LabeledContent("Time", value: "\(DateUtils.displayTime(session.startTime)) – \(DateUtils.displayTime(session.endTime))")
                }
                Section("Attendance") {
                    ForEach(0..<count, id: \.self) { index in
                        Picker(count > 1 ? "Unit \(index + 1)" : "Status", selection: binding(for: index)) {
                            ForEach(AttendanceStatus.allCases, id: \.self) { status in
                                Text(status.label).tag(status)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
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

    private func binding(for index: Int) -> Binding<AttendanceStatus> {
        Binding(
            get: { session.units.first(where: { $0.unitIndex == index })?.status ?? .unmarked },
            set: { newValue in
                if let unit = session.units.first(where: { $0.unitIndex == index }) {
                    unit.status = newValue
                    unit.markedAt = Date()
                } else {
                    let unit = AttendanceUnit(unitIndex: index, status: newValue)
                    context.insert(unit)
                    unit.session = session
                }
                do { try context.save() } catch { errorText = error.localizedDescription }
            }
        )
    }
}

struct AddPastClassView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Subject.name) private var subjects: [Subject]

    @State private var subjectID: UUID?
    @State private var date = Date()
    @State private var start = DateUtils.time(from: "09:00")
    @State private var end = DateUtils.time(from: "10:00")
    @State private var units = 1
    @State private var status: AttendanceStatus = .present
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Class") {
                    Picker("Subject", selection: $subjectID) {
                        Text("Select…").tag(UUID?.none)
                        ForEach(subjects.filter { !$0.isArchived }) { s in
                            Text(s.name).tag(Optional(s.id))
                        }
                    }
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
                    Stepper("Attendance units: \(units)", value: $units, in: 1...6)
                }
                Section("Mark all units as") {
                    Picker("Status", selection: $status) {
                        ForEach(AttendanceStatus.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationTitle("Add Past Class")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(subjectID == nil)
                }
            }
            .onChange(of: subjectID) { _, newValue in
                if let s = subjects.first(where: { $0.id == newValue }) { units = s.defaultAttendanceUnits }
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
        guard let subject = subjects.first(where: { $0.id == subjectID }) else { return }
        let startStr = DateUtils.hhmm(start)
        let endStr = DateUtils.hhmm(end)
        guard endStr > startStr else {
            errorText = "The end time must be after the start time."
            return
        }
        let session = AttendanceSession(
            sessionDate: DateUtils.isoString(date), startTime: startStr, endTime: endStr,
            expectedUnitCount: units
        )
        context.insert(session)
        session.subject = subject
        for index in 0..<units {
            let unit = AttendanceUnit(unitIndex: index, status: status)
            context.insert(unit)
            unit.session = session
        }
        do {
            try context.save()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
