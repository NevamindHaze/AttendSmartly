import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab: DashboardTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeDashboardView()
            }
            .tabItem {
                Label(DashboardTab.home.title, systemImage: DashboardTab.home.symbol)
            }
            .tag(DashboardTab.home)

            SubjectsView()
                .tabItem {
                    Label(DashboardTab.subjects.title, systemImage: DashboardTab.subjects.symbol)
                }
                .tag(DashboardTab.subjects)
            placeholderTab(.timetable, message: "Your weekly class schedule will appear here.")
            placeholderTab(.history, message: "Your attendance records will appear here.")
            placeholderTab(.analytics, message: "Your attendance insights will appear here.")
        }
        .tint(DashboardPalette.green)
    }

    private func placeholderTab(_ tab: DashboardTab, message: String) -> some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(DashboardPalette.green)
                Text(tab.title)
                    .font(.title3.bold())
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .navigationTitle(tab.title)
            .navigationBarTitleDisplayMode(.large)
        }
        .tabItem {
            Label(tab.title, systemImage: tab.symbol)
        }
        .tag(tab)
    }
}

private struct SubjectsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Subject.name) private var subjects: [Subject]

    @State private var showingArchived = false
    @State private var showingSubjectForm = false
    @State private var subjectToEdit: Subject?
    @State private var saveError: String?

    private var visibleSubjects: [Subject] {
        subjects.filter { $0.isArchived == showingArchived }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleSubjects.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(visibleSubjects) { subject in
                            Button {
                                subjectToEdit = subject
                                showingSubjectForm = true
                            } label: {
                                SubjectRowView(subject: subject)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    toggleArchive(subject)
                                } label: {
                                    Label(
                                        subject.isArchived ? "Unarchive" : "Archive",
                                        systemImage: subject.isArchived ? "tray.and.arrow.up" : "archivebox"
                                    )
                                }
                                .tint(subject.isArchived ? DashboardPalette.green : .orange)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Subjects")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingArchived.toggle()
                    } label: {
                        Label(
                            showingArchived ? "Active" : "Archived",
                            systemImage: showingArchived ? "books.vertical" : "archivebox"
                        )
                    }
                    .accessibilityLabel(showingArchived ? "Show active subjects" : "Show archived subjects")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        subjectToEdit = nil
                        showingSubjectForm = true
                    } label: {
                        Label("Add Subject", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingSubjectForm, onDismiss: {
                subjectToEdit = nil
            }) {
                SubjectFormView(subject: subjectToEdit)
            }
            .alert("Couldn't Save Changes", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) {
                    saveError = nil
                }
            } message: {
                Text(saveError ?? "Please try again.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: showingArchived ? "archivebox" : "book.closed")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(DashboardPalette.green)
            Text(showingArchived ? "No archived subjects" : "No subjects yet")
                .font(.title3.bold())
            Text(
                showingArchived
                    ? "Subjects you archive will appear here."
                    : "Add your first subject to start organizing your classes."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            if !showingArchived {
                Button {
                    subjectToEdit = nil
                    showingSubjectForm = true
                } label: {
                    Label("Add Subject", systemImage: "plus")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(DashboardPalette.green)
                .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func toggleArchive(_ subject: Subject) {
        let previousValue = subject.isArchived
        subject.isArchived.toggle()

        do {
            try modelContext.save()
        } catch {
            subject.isArchived = previousValue
            saveError = error.localizedDescription
        }
    }
}

private struct SubjectRowView: View {
    let subject: Subject

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(SubjectColorOption(rawValue: subject.colorIdentifier)?.color ?? .gray)
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(subject.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if subject.isArchived {
                        Text("Archived")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }

                Text("Target: \(subject.attendanceTarget, specifier: "%.1f")%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !subject.notes.isEmpty {
                    Text(subject.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

private struct SubjectFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let subject: Subject?

    @State private var name: String
    @State private var attendanceTargetText: String
    @State private var isArchived: Bool
    @State private var notes: String
    @State private var colorIdentifier: String
    @State private var validationMessage: String?
    @State private var saveError: String?

    init(subject: Subject?) {
        self.subject = subject
        _name = State(initialValue: subject?.name ?? "")
        _attendanceTargetText = State(initialValue: String(subject?.attendanceTarget ?? 75))
        _isArchived = State(initialValue: subject?.isArchived ?? false)
        _notes = State(initialValue: subject?.notes ?? "")
        _colorIdentifier = State(initialValue: subject?.colorIdentifier ?? "green")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Subject details") {
                    TextField("Subject name", text: $name)
                        .textInputAutocapitalization(.words)

                    HStack {
                        Text("Attendance target")
                        Spacer()
                        TextField("75", text: $attendanceTargetText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("%")
                            .foregroundStyle(.secondary)
                    }

                    Picker("Color", selection: $colorIdentifier) {
                        ForEach(SubjectColorOption.allCases) { option in
                            Label(option.title, systemImage: "circle.fill")
                                .foregroundStyle(option.color)
                                .tag(option.rawValue)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Toggle("Archived", isOn: $isArchived)
                } footer: {
                    Text("Archived subjects are hidden from the active list but are not deleted.")
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(subject == nil ? "Add Subject" : "Edit Subject")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveSubject)
                }
            }
            .alert("Couldn't Save Subject", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) {
                    saveError = nil
                }
            } message: {
                Text(saveError ?? "Please try again.")
            }
        }
    }

    private func saveSubject() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Enter a subject name."
            return
        }

        guard
            let target = Double(attendanceTargetText.trimmingCharacters(in: .whitespacesAndNewlines)),
            (1...100).contains(target)
        else {
            validationMessage = "Enter a target percentage from 1 to 100."
            return
        }

        validationMessage = nil

        let originalName = subject?.name
        let originalTarget = subject?.attendanceTarget
        let originalArchiveStatus = subject?.isArchived
        let originalNotes = subject?.notes
        let originalColorIdentifier = subject?.colorIdentifier
        var insertedSubject: Subject?

        if let subject {
            subject.name = trimmedName
            subject.attendanceTarget = target
            subject.isArchived = isArchived
            subject.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            subject.colorIdentifier = colorIdentifier
        } else {
            let newSubject = Subject(
                name: trimmedName,
                attendanceTarget: target,
                isArchived: isArchived,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                colorIdentifier: colorIdentifier
            )
            modelContext.insert(newSubject)
            insertedSubject = newSubject
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            if let subject {
                subject.name = originalName ?? subject.name
                subject.attendanceTarget = originalTarget ?? subject.attendanceTarget
                subject.isArchived = originalArchiveStatus ?? subject.isArchived
                subject.notes = originalNotes ?? subject.notes
                subject.colorIdentifier = originalColorIdentifier ?? subject.colorIdentifier
            }
            if let insertedSubject {
                modelContext.delete(insertedSubject)
            }
            saveError = error.localizedDescription
        }
    }
}

private enum SubjectColorOption: String, CaseIterable, Identifiable {
    case green
    case blue
    case coral

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .green: DashboardPalette.green
        case .blue: DashboardPalette.blue
        case .coral: DashboardPalette.coral
        }
    }
}

private struct HomeDashboardView: View {
    private let attendedClasses = 18
    private let totalClasses = 20
    private let scheduledClasses = [
        ScheduledClass(
            startTime: "9:00 AM",
            endTime: "10:00 AM",
            subject: "Data Structures",
            code: "CSE 201",
            room: "Engineering Hall 204",
            color: DashboardPalette.green
        ),
        ScheduledClass(
            startTime: "11:00 AM",
            endTime: "12:30 PM",
            subject: "Linear Algebra",
            code: "MATH 101",
            room: "North Hall 118",
            color: DashboardPalette.blue
        ),
        ScheduledClass(
            startTime: "2:00 PM",
            endTime: "3:30 PM",
            subject: "Design Studio",
            code: "DES 220",
            room: "Arts Building 12",
            color: DashboardPalette.coral
        )
    ]

    private var attendanceRate: Double {
        Double(attendedClasses) / Double(totalClasses)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AttendSmartly")
                        .font(.largeTitle.bold())
                        .foregroundStyle(DashboardPalette.ink)
                    Label(
                        Date.now.formatted(date: .complete, time: .omitted),
                        systemImage: "calendar"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                attendanceSummary

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Today's classes")
                            .font(.title2.bold())
                            .foregroundStyle(DashboardPalette.ink)
                        Spacer()
                        Text("\(scheduledClasses.count) scheduled")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(scheduledClasses.enumerated()), id: \.element.id) { index, classItem in
                            ScheduledClassRow(classItem: classItem)

                            if index < scheduledClasses.count - 1 {
                                Divider()
                                    .padding(.leading, 94)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var attendanceSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overall attendance")
                        .font(.headline)
                        .foregroundStyle(DashboardPalette.ink)
                    Text("Across all subjects")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text("On track")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardPalette.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DashboardPalette.green.opacity(0.1), in: Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(attendanceRate * 100))%")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(DashboardPalette.green)
                Text("attendance")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: attendanceRate)
                .tint(DashboardPalette.green)

            HStack(spacing: 0) {
                attendanceMetric(value: attendedClasses, label: "Attended")
                Spacer()
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 1, height: 30)
                Spacer()
                attendanceMetric(value: totalClasses, label: "Total classes")
            }
            .padding(.top, 2)
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func attendanceMetric(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .font(.title3.bold())
                .foregroundStyle(DashboardPalette.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ScheduledClass: Identifiable {
    let id = UUID()
    let startTime: String
    let endTime: String
    let subject: String
    let code: String
    let room: String
    let color: Color
}

private struct ScheduledClassRow: View {
    let classItem: ScheduledClass

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(classItem.startTime)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DashboardPalette.ink)
                Text(classItem.endTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 66, alignment: .leading)

            RoundedRectangle(cornerRadius: 2)
                .fill(classItem.color)
                .frame(width: 4, height: 44)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(classItem.subject)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DashboardPalette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(classItem.code)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Label(classItem.room, systemImage: "mappin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
    }
}

private enum DashboardTab: String, CaseIterable {
    case home
    case subjects
    case timetable
    case history
    case analytics

    var title: String {
        switch self {
        case .home: "Home"
        case .subjects: "Subjects"
        case .timetable: "Timetable"
        case .history: "History"
        case .analytics: "Analytics"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .subjects: "book.closed"
        case .timetable: "calendar"
        case .history: "clock.arrow.circlepath"
        case .analytics: "chart.bar.xaxis"
        }
    }
}

private enum DashboardPalette {
    static let green = Color(red: 0.12, green: 0.42, blue: 0.34)
    static let blue = Color(red: 0.26, green: 0.48, blue: 0.72)
    static let coral = Color(red: 0.82, green: 0.38, blue: 0.29)
    static let ink = Color.primary
}

#Preview {
    ContentView()
}