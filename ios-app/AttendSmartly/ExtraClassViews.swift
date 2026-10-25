import SwiftUI
import SwiftData

/// Add a one-off class that isn't in the weekly timetable.
struct AddExtraClassView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Subject.name) private var subjects: [Subject]

    @State private var subjectID: UUID?
    @State private var date = Date()
    @State private var start = DateUtils.time(from: "09:00")
    @State private var end = DateUtils.time(from: "10:00")
    @State private var units = 1
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Extra class") {
                    Picker("Subject", selection: $subjectID) {
                        Text("Select…").tag(UUID?.none)
                        ForEach(subjects.filter { !$0.isArchived }) { s in
                            Text(s.name).tag(Optional(s.id))
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
                    Stepper("Attendance units: \(units)", value: $units, in: 1...6)
                }
            }
            .navigationTitle("Add Extra Class")
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
        session.notes = "Extra class"
        context.insert(session)
        session.subject = subject
        do {
            try context.save()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Move today's class to another date/time.
struct RescheduleView: View {
    @Environment(\.dismiss) private var dismiss

    let row: TodayClass
    let onConfirm: (Date, String, String) -> Void

    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var start: Date
    @State private var end: Date
    @State private var errorText: String?

    init(row: TodayClass, onConfirm: @escaping (Date, String, String) -> Void) {
        self.row = row
        self.onConfirm = onConfirm
        _start = State(initialValue: DateUtils.time(from: row.start))
        _end = State(initialValue: DateUtils.time(from: row.end))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Class", value: row.subject.name)
                    LabeledContent("Currently", value: "\(DateUtils.displayTime(row.start)) – \(DateUtils.displayTime(row.end))")
                }
                Section("Move to") {
                    DatePicker("New date", selection: $date, in: Date()..., displayedComponents: .date)
                    DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
                }
                Section {
                    Text("Today's class is marked cancelled, and a new class is added on the new date.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reschedule") {
                        let startStr = DateUtils.hhmm(start)
                        let endStr = DateUtils.hhmm(end)
                        guard endStr > startStr else {
                            errorText = "The end time must be after the start time."
                            return
                        }
                        onConfirm(date, startStr, endStr)
                        dismiss()
                    }
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
}
