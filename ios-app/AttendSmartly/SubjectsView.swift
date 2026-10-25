import SwiftUI
import SwiftData

struct SubjectsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Subject.name) private var subjects: [Subject]

    @State private var showingArchived = false
    @State private var formSubject: Subject?
    @State private var showingForm = false
    @State private var subjectToDelete: Subject?
    @State private var errorText: String?

    private var visible: [Subject] {
        subjects.filter { $0.isArchived == showingArchived }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visible.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(visible) { subject in
                            Button {
                                formSubject = subject
                                showingForm = true
                            } label: {
                                SubjectRow(subject: subject)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    subjectToDelete = subject
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    toggleArchive(subject)
                                } label: {
                                    Label(
                                        subject.isArchived ? "Unarchive" : "Archive",
                                        systemImage: subject.isArchived ? "tray.and.arrow.up" : "archivebox"
                                    )
                                }
                                .tint(.orange)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(showingArchived ? "Archived" : "Subjects")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingArchived.toggle() } label: {
                        Label(showingArchived ? "Active" : "Archived",
                              systemImage: showingArchived ? "books.vertical" : "archivebox")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        formSubject = nil
                        showingForm = true
                    } label: {
                        Label("Add Subject", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingForm, onDismiss: { formSubject = nil }) {
                SubjectFormView(subject: formSubject)
            }
            .alert("Delete subject?", isPresented: Binding(
                get: { subjectToDelete != nil },
                set: { if !$0 { subjectToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let s = subjectToDelete { delete(s) }
                    subjectToDelete = nil
                }
                Button("Cancel", role: .cancel) { subjectToDelete = nil }
            } message: {
                Text("This also deletes its timetable entries and all attendance records for it.")
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: showingArchived ? "archivebox" : "book.closed")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(DashboardPalette.green)
            Text(showingArchived ? "No archived subjects" : "No subjects yet").font(.title3.bold())
            Text(showingArchived
                 ? "Subjects you archive will appear here."
                 : "Add a subject, or import your Android backup from Settings on the Home tab.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggleArchive(_ subject: Subject) {
        subject.isArchived.toggle()
        save()
    }

    private func delete(_ subject: Subject) {
        context.delete(subject)
        save()
    }

    private func save() {
        do { try context.save() } catch { errorText = error.localizedDescription }
    }
}

private struct SubjectRow: View {
    let subject: Subject

    var body: some View {
        let summary = AttendanceCalculator.summary(
            statuses: subject.sessions.flatMap { $0.units.map { $0.status } },
            target: subject.targetPercentage
        )
        let onTrack = summary.conducted == 0 || summary.percentage >= summary.target
        let tint = onTrack ? DashboardPalette.green : DashboardPalette.coral

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle().fill(Color(argb: subject.colorValue)).frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(subject.name).font(.headline)
                    let sub = [subject.code, subject.type, subject.teacherName].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Text(summary.conducted == 0 ? "–" : "\(Int(summary.percentage.rounded()))%")
                    .font(.title3.bold())
                    .foregroundStyle(tint)
            }
            if summary.conducted > 0 {
                ProgressView(value: min(summary.percentage, 100), total: 100).tint(tint)
            }
            Text(summary.message).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct SubjectFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let subject: Subject?

    @State private var name: String
    @State private var code: String
    @State private var type: String
    @State private var teacher: String
    @State private var room: String
    @State private var target: Double
    @State private var units: Int
    @State private var colorValue: Int
    @State private var notes: String
    @State private var errorText: String?

    private static let types = ["Lecture", "Lab", "Tutorial", "Seminar", "Other"]
    private static let palette: [Int] = [
        0xFF2196F3, 0xFF4CAF50, 0xFFE91E63, 0xFFFF9800,
        0xFF9C27B0, 0xFF009688, 0xFFF44336, 0xFF607D8B
    ]

    init(subject: Subject?) {
        self.subject = subject
        _name = State(initialValue: subject?.name ?? "")
        _code = State(initialValue: subject?.code ?? "")
        _type = State(initialValue: subject?.type ?? "Lecture")
        _teacher = State(initialValue: subject?.teacherName ?? "")
        _room = State(initialValue: subject?.room ?? "")
        _target = State(initialValue: subject?.targetPercentage ?? 75)
        _units = State(initialValue: subject?.defaultAttendanceUnits ?? 1)
        _colorValue = State(initialValue: subject?.colorValue ?? 0xFF4CAF50)
        _notes = State(initialValue: subject?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Subject") {
                    TextField("Name", text: $name)
                        .submitLabel(.done)
                    TextField("Code (optional)", text: $code)
                    Picker("Type", selection: $type) {
                        ForEach(Self.types, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Teacher (optional)", text: $teacher)
                    TextField("Room (optional)", text: $room)
                }

                Section("Attendance") {
                    VStack(alignment: .leading) {
                        Text("Target: \(Int(target))%")
                        Slider(value: $target, in: 50...100, step: 1)
                    }
                    Stepper("Units per class: \(units)", value: $units, in: 1...6)
                }

                Section("Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(Self.palette, id: \.self) { value in
                            Circle()
                                .fill(Color(argb: value))
                                .frame(width: 28, height: 28)
                                .overlay(Circle().stroke(Color.primary, lineWidth: colorValue == value ? 3 : 0))
                                .onTapGesture { colorValue = value }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(subject == nil ? "New Subject" : "Edit Subject")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                        )
                    }
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

    private func save() {
        let target_ = subject ?? Subject(name: name)
        target_.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target_.code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        target_.type = type
        target_.teacherName = teacher.trimmingCharacters(in: .whitespacesAndNewlines)
        target_.room = room.trimmingCharacters(in: .whitespacesAndNewlines)
        target_.targetPercentage = target
        target_.defaultAttendanceUnits = units
        target_.colorValue = colorValue
        target_.notes = notes
        if subject == nil { context.insert(target_) }
        do {
            try context.save()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
