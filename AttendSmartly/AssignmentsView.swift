import SwiftUI
import SwiftData

// MARK: - Full list

struct AssignmentsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @Query(sort: \Subject.name) private var subjects: [Subject]

    /// Show only one subject's assignments (used from a subject page).
    var subjectFilter: UUID? = nil

    @State private var showDone = false
    @State private var editing: Assignment?
    @State private var showNew = false
    @State private var toDelete: Assignment?

    var body: some View {
        let now = Date()
        let mine = assignments.filter { subjectFilter == nil || $0.subjectID == subjectFilter }
        let open = mine.filter { !$0.isCompleted }
        let done = mine.filter { $0.isCompleted }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        List {
            Section {
                Picker("Show", selection: $showDone) {
                    Text("To do (\(open.count))").tag(false)
                    Text("Done (\(done.count))").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            if showDone {
                if done.isEmpty {
                    empty("checkmark.circle", "Nothing finished yet", "Tick the circle on an assignment when you hand it in.")
                } else {
                    ForEach(done) { row($0, now: now) }
                }
            } else if open.isEmpty {
                empty("tray", "You're all caught up", "Tap + to add an assignment and its due date.")
            } else {
                group("Overdue", open.filter { if case .overdue = $0.status(now: now) { return true }; return false }, now: now)
                group("Due today", open.filter { $0.status(now: now) == .dueToday }, now: now)
                group("Due in the next 3 days", open.filter { $0.status(now: now) == .dueSoon }, now: now)
                group("Later", open.filter { $0.status(now: now) == .upcoming }, now: now)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Pastel.background)
        .navigationTitle("Assignments")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNew = true } label: { Label("Add assignment", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showNew) { AssignmentFormView(assignment: nil, defaultSubject: subjectFilter) }
        .sheet(item: $editing) { AssignmentFormView(assignment: $0, defaultSubject: nil) }
        .alert("Delete this assignment?", isPresented: Binding(
            get: { toDelete != nil },
            set: { if !$0 { toDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let a = toDelete {
                    context.delete(a)
                    try? context.save()
                }
                toDelete = nil
            }
            Button("Cancel", role: .cancel) { toDelete = nil }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [Assignment], now: Date) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { row($0, now: now) }
            } header: {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Pastel.ink)
                    .textCase(nil)
                    .padding(.leading, 4)
            }
            .listSectionSeparator(.hidden)
        }
    }

    private func row(_ assignment: Assignment, now: Date) -> some View {
        AssignmentRow(
            assignment: assignment,
            subject: subjects.first { $0.id == assignment.subjectID },
            now: now
        )
        .contentShape(Rectangle())
        .onTapGesture { editing = assignment }
        .pastelRow(assignment.status(now: now).tile)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { toDelete = assignment } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func empty(_ symbol: String, _ title: String, _ message: String) -> some View {
        EmptyStateView(symbol: symbol, title: title, message: message)
            .tile(Pastel.surface)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - Row

struct AssignmentRow: View {
    @Environment(\.modelContext) private var context
    let assignment: Assignment
    let subject: Subject?
    let now: Date

    var body: some View {
        let status = assignment.status(now: now)
        HStack(alignment: .top, spacing: 14) {
            Button(action: toggle) {
                Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(assignment.isCompleted ? status.tint : Pastel.ink.opacity(0.55))
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: assignment.isCompleted)
            .accessibilityLabel(assignment.isCompleted ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 6) {
                Text(assignment.title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .strikethrough(assignment.isCompleted, color: Pastel.ink.opacity(0.5))
                if let subject {
                    HStack(spacing: 6) {
                        Circle().fill(Pastel.subjectStrong(subject.colorValue)).frame(width: 8, height: 8)
                        Text(subject.name).font(.footnote.weight(.medium)).opacity(0.75)
                    }
                }
                Label("Due \(AssignmentFormat.due(assignment.dueDate, now: now))", systemImage: "calendar")
                    .font(.footnote)
                    .opacity(0.75)
                Label(status.label, systemImage: status.symbol)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(status.tint, in: Capsule())
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Pastel.ink)
    }

    private func toggle() {
        withAnimation(.snappy) {
            assignment.completedAt = assignment.isCompleted ? nil : Date()
        }
        try? context.save()
    }
}

// MARK: - Add / edit

struct AssignmentFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Subject.name) private var subjects: [Subject]

    let assignment: Assignment?

    @State private var title: String
    @State private var subjectID: UUID?
    @State private var due: Date
    @State private var notes: String
    @State private var isDone: Bool
    @State private var doneAt: Date

    init(assignment: Assignment?, defaultSubject: UUID?) {
        self.assignment = assignment
        _title = State(initialValue: assignment?.title ?? "")
        _subjectID = State(initialValue: assignment?.subjectID ?? defaultSubject)
        _due = State(initialValue: assignment?.dueDate ?? Self.defaultDue())
        _notes = State(initialValue: assignment?.notes ?? "")
        _isDone = State(initialValue: assignment?.isCompleted ?? false)
        _doneAt = State(initialValue: assignment?.completedAt ?? Date())
    }

    /// Tomorrow at 11:59 PM.
    private static func defaultDue() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: tomorrow) ?? tomorrow
    }

    var body: some View {
        let preview = AssignmentStatus.of(due: due, completedAt: isDone ? doneAt : nil, now: Date())
        NavigationStack {
            Form {
                Section {
                    TextField("What's the assignment?", text: $title, axis: .vertical)
                        .font(.headline)
                    Picker("Subject", selection: $subjectID) {
                        Text("None").tag(UUID?.none)
                        ForEach(subjects.filter { !$0.isArchived || $0.id == subjectID }) { s in
                            Text(s.name).tag(Optional(s.id))
                        }
                    }
                }

                Section("Due") {
                    DatePicker("Due", selection: $due)
                    HStack(spacing: 8) {
                        quickDue("Today", days: 0)
                        quickDue("Tomorrow", days: 1)
                        quickDue("In a week", days: 7)
                    }
                    .buttonStyle(.bordered)
                    .font(.footnote.weight(.semibold))
                }

                Section {
                    Toggle("Handed in", isOn: $isDone)
                    if isDone {
                        DatePicker("Handed in on", selection: $doneAt)
                    }
                } footer: {
                    Label(preview.label, systemImage: preview.symbol)
                        .foregroundStyle(preview.tint)
                        .font(.footnote.weight(.semibold))
                }

                Section("Notes") {
                    TextField("Pages, word count, where to submit…", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if let assignment {
                    Section {
                        Button("Delete assignment", role: .destructive) {
                            context.delete(assignment)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(assignment == nil ? "New Assignment" : "Edit Assignment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func quickDue(_ title: String, days: Int) -> some View {
        Button(title) {
            let calendar = Calendar.current
            let day = calendar.date(byAdding: .day, value: days, to: Date()) ?? Date()
            due = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? day
        }
    }

    private func save() {
        let target = assignment ?? Assignment(title: "", dueDate: due)
        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.subjectID = subjectID
        target.dueDate = due
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.completedAt = isDone ? doneAt : nil
        if assignment == nil { context.insert(target) }
        try? context.save()
        if UserDefaults.standard.object(forKey: PrefKey.assignmentRemindersEnabled) as? Bool ?? true {
            Task { await ReminderService.requestAuthorizationIfNeeded() }
        }
        dismiss()
    }
}

// MARK: - Home card

struct HomeAssignmentsCard: View {
    @Query(filter: #Predicate<Assignment> { $0.completedAt == nil }, sort: \Assignment.dueDate)
    private var open: [Assignment]
    @Query private var subjects: [Subject]

    var body: some View {
        let now = Date()
        let overdue = open.filter { $0.dueDate < now }.count
        let today = open.filter { $0.status(now: now) == .dueToday }.count
        let soon = open.filter { $0.status(now: now) == .dueSoon }.count
        let next = open.first { $0.dueDate >= now } ?? open.first
        let color = overdue > 0 ? Pastel.pink : (today + soon > 0 ? Pastel.butter : Pastel.mint)

        NavigationLink {
            AssignmentsView()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "checklist")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 34, height: 34)
                        .background(Pastel.surface.opacity(0.75), in: Circle())
                    Text("Assignments")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .opacity(0.5)
                }

                if open.isEmpty {
                    Text("Nothing due. Tap to add an assignment.")
                        .font(.subheadline)
                        .opacity(0.75)
                } else {
                    HStack(spacing: 8) {
                        count(overdue, "overdue", overdue > 0)
                        count(today, "due today", today > 0)
                        count(soon, "next 3 days", false)
                    }
                    if let next {
                        let status = next.status(now: now)
                        HStack(spacing: 8) {
                            Circle()
                                .fill(status.tint)
                                .frame(width: 8, height: 8)
                            Text(next.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(status.isOpen && next.dueDate < now
                                 ? status.label
                                 : AssignmentFormat.due(next.dueDate, now: now))
                                .font(.caption.weight(.medium))
                                .opacity(0.75)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Pastel.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
            .foregroundStyle(Pastel.ink)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tile(color, radius: 26)
        }
        .buttonStyle(.plain)
    }

    private func count(_ value: Int, _ label: String, _ highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .monospacedDigit()
            Text(label)
                .font(.caption2.weight(.semibold))
                .opacity(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            highlight ? Pastel.surface.opacity(0.9) : Pastel.surface.opacity(0.5),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}
