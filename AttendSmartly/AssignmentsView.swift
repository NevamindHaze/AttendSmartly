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
    @State private var expanded: Set<UUID> = []
    @AppStorage(PrefKey.assignmentGrouping) private var grouping = AssignmentGrouping.due.rawValue

    var body: some View {
        let now = Date()
        let mine = assignments.filter { subjectFilter == nil || $0.subjectID == subjectFilter }
        let open = mine.filter { !$0.isCompleted }
        let done = mine.filter { $0.isCompleted }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        let items = showDone ? done : open

        // A plain stack rather than a List (List resized rows out of step with their
        // contents) and not a LazyVStack (it kept stale heights for expanded cards).
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Show", selection: $showDone) {
                    Text("To do (\(open.count))").tag(false)
                    Text("Done (\(done.count))").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)

                if items.isEmpty {
                    if showDone {
                        empty("checkmark.circle", "Nothing finished yet", "Tick the circle on an assignment when you hand it in.")
                    } else {
                        empty("tray", "You're all caught up", "Tap + to add an assignment and its due date.")
                    }
                } else {
                    let grouped = AssignmentGrouping(rawValue: grouping) ?? .due
                    ForEach(grouped.sections(of: items, subjects: subjects, now: now)) { section in
                        header(section)
                        ForEach(section.items) { row($0, now: now) }
                    }
                }
            }
            .padding()
        }
        .background(Pastel.background)
        .navigationTitle("Assignments")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Group by", selection: $grouping) {
                        ForEach(AssignmentGrouping.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                } label: {
                    Label("Group by", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
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

    private func header(_ section: AssignmentSection) -> some View {
        HStack(spacing: 6) {
            if let dot = section.dot { Circle().fill(Pastel.subjectStrong(dot)).frame(width: 10, height: 10) }
            if let symbol = section.symbol { Image(systemName: symbol) }
            Text(section.title)
            Text("\(section.items.count)").opacity(0.5)
        }
        .font(.system(.subheadline, design: .rounded).weight(.bold))
        .foregroundStyle(Pastel.ink)
        .padding(.leading, 4)
        .padding(.top, 10)
        .accessibilityAddTraits(.isHeader)
    }

    private func row(_ assignment: Assignment, now: Date) -> some View {
        let subject = subjects.first { $0.id == assignment.subjectID }
        let isOpen = expanded.contains(assignment.id)
        return AssignmentRow(
            assignment: assignment,
            subject: subject,
            now: now,
            isExpanded: isOpen,
            onEdit: { editing = assignment }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(subject.map { Pastel.subject($0.colorValue) } ?? Pastel.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            withAnimation(.snappy(duration: 0.3)) {
                if isOpen { expanded.remove(assignment.id) } else { expanded.insert(assignment.id) }
            }
        }
        .accessibilityHint(isOpen ? "Hides the details" : "Shows the details")
        .contextMenu {
            Button { editing = assignment } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { toDelete = assignment } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func empty(_ symbol: String, _ title: String, _ message: String) -> some View {
        EmptyStateView(symbol: symbol, title: title, message: message)
            .tile(Pastel.surface)
    }
}

enum AssignmentGrouping: String, CaseIterable, Identifiable {
    case due, subject, type
    var id: String { rawValue }
    var label: String {
        switch self {
        case .due: return "Due date"
        case .subject: return "Subject"
        case .type: return "Type"
        }
    }

    /// The headed groups shown in the list, empty ones left out. `items` is either all
    /// open or all done assignments, already in display order.
    func sections(of items: [Assignment], subjects: [Subject], now: Date) -> [AssignmentSection] {
        func by(_ title: String, _ match: (AssignmentStatus) -> Bool) -> AssignmentSection {
            AssignmentSection(id: title, title: title, items: items.filter { match($0.status(now: now)) })
        }
        let all: [AssignmentSection]
        switch self {
        case .subject:
            all = subjects.map { s in
                AssignmentSection(id: s.id.uuidString, title: s.name, dot: s.colorValue, items: items.filter { $0.subjectID == s.id })
            } + [AssignmentSection(id: "none", title: "No subject", items: items.filter { a in !subjects.contains { $0.id == a.subjectID } })]
        case .type:
            all = AssignmentKind.allCases.map { kind in
                AssignmentSection(id: kind.rawValue, title: kind.rawValue, symbol: kind.symbol, items: items.filter { $0.kindValue == kind })
            }
        case .due:
            all = [
                by("Overdue") { if case .overdue = $0 { return true }; return false },
                by("Due today") { $0 == .dueToday },
                by("Due in the next 3 days") { $0 == .dueSoon },
                by("Later") { $0 == .upcoming },
                by("Handed in late") { if case .doneLate = $0 { return true }; return false },
                by("Handed in on time") { $0 == .doneOnTime }
            ]
        }
        return all.filter { !$0.items.isEmpty }
    }
}

struct AssignmentSection: Identifiable {
    let id: String
    let title: String
    var dot: Int? = nil
    var symbol: String? = nil
    let items: [Assignment]
}

// MARK: - Row

struct AssignmentRow: View {
    @Environment(\.modelContext) private var context
    let assignment: Assignment
    let subject: Subject?
    let now: Date
    var isExpanded = false
    var onEdit: () -> Void = {}

    var body: some View {
        let status = assignment.status(now: now)
        let kind = assignment.kindValue
        HStack(alignment: .top, spacing: 12) {
            Button(action: toggle) {
                Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(assignment.isCompleted ? status.tint : Pastel.ink.opacity(0.55))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: assignment.isCompleted)
            .accessibilityLabel(assignment.isCompleted ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 4) {
                Text(assignment.displayTitle)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .strikethrough(assignment.isCompleted, color: Pastel.ink.opacity(0.5))
                    .lineLimit(isExpanded ? nil : 1)
                    // Re-wrapping text can't animate; animating it draws both layouts at once.
                    .transaction { $0.animation = nil }
                HStack(spacing: 5) {
                    Image(systemName: kind.symbol)
                    if let subject {
                        Text(subject.name).lineLimit(1)
                        Text("·")
                    }
                    Text(AssignmentFormat.due(assignment.dueDate, now: now)).lineLimit(1)
                }
                .font(.caption.weight(.medium))
                .opacity(0.75)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(kind.rawValue, systemImage: kind.symbol)
                        if !assignment.instructor.isEmpty {
                            Label(assignment.instructor, systemImage: "person")
                        }
                        Label("Due \(AssignmentFormat.due(assignment.dueDate, now: now))", systemImage: "calendar")
                        if !assignment.notes.isEmpty {
                            Label(assignment.notes, systemImage: "note.text")
                        }
                        if !assignment.isCompleted {
                            DeadlineBar(assignment: assignment, now: now)
                        }
                        HStack {
                            Label(status.label, systemImage: status.symbol)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(status.tint, in: Capsule())
                                .foregroundStyle(.white)
                            Spacer()
                            Button("Edit", systemImage: "pencil", action: onEdit)
                                .font(.caption.weight(.bold))
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .tint(Pastel.ink)
                        }
                    }
                    .font(.footnote)
                    .padding(.top, 4)
                    .transition(.opacity)
                }
            }
            Spacer(minLength: 0)

            // Status at a glance; the full wording shows when expanded.
            Image(systemName: status.symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(status.tint, in: Circle())
                .accessibilityLabel(status.label)
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
    @Query private var allAssignments: [Assignment]
    @AppStorage(PrefKey.assignmentAutoNumber) private var autoNumber = true

    let assignment: Assignment?

    @State private var title: String
    @State private var kind: AssignmentKind
    @State private var number: Int
    @State private var instructor: String
    @State private var showNewSubject = false
    /// The instructor the app last filled in, so it can be swapped while you haven't typed your own.
    @State private var autoInstructor = ""
    @State private var didAppear = false
    @State private var subjectID: UUID?
    @State private var assigned: Date
    @State private var customDue: Bool
    @State private var due: Date
    @State private var notes: String
    @State private var isDone: Bool
    @State private var doneAt: Date

    private let deadlineDays = Assignment.deadlineDays

    init(assignment: Assignment?, defaultSubject: UUID?) {
        self.assignment = assignment
        let assigned = assignment?.assignedDate ?? Date()
        _title = State(initialValue: assignment?.title ?? "")
        _subjectID = State(initialValue: assignment?.subjectID ?? defaultSubject)
        _kind = State(initialValue: assignment?.kindValue ?? .assignment)
        _number = State(initialValue: assignment?.number ?? 0)
        _instructor = State(initialValue: assignment?.instructor ?? "")
        _assigned = State(initialValue: assigned)
        _customDue = State(initialValue: assignment?.hasCustomDue ?? false)
        _due = State(initialValue: assignment?.dueDate
            ?? Assignment.dueDate(assignedOn: assigned, days: Assignment.deadlineDays))
        _notes = State(initialValue: assignment?.notes ?? "")
        _isDone = State(initialValue: assignment?.isCompleted ?? false)
        _doneAt = State(initialValue: assignment?.completedAt ?? Date())
    }

    /// The due date that will be saved.
    private var effectiveDue: Date {
        customDue ? due : Assignment.dueDate(assignedOn: assigned, days: deadlineDays)
    }

    var body: some View {
        let preview = AssignmentStatus.of(due: effectiveDue, completedAt: isDone ? doneAt : nil, now: Date())
        NavigationStack {
            Form {
                Section {
                    TextField(number > 0 ? "Title (optional)" : "What's the assignment?", text: $title, axis: .vertical)
                        .font(.headline)
                    Picker("Type", selection: $kind) {
                        ForEach(AssignmentKind.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }
                    Picker("Subject", selection: $subjectID) {
                        Text("None").tag(UUID?.none)
                        ForEach(subjects.filter { !$0.isArchived || $0.id == subjectID }) { s in
                            Text(s.name).tag(Optional(s.id))
                        }
                    }
                    Button { showNewSubject = true } label: {
                        Label("New subject", systemImage: "plus.circle")
                    }
                    Stepper(number > 0 ? "Number: \(number)" : "Not numbered", value: $number, in: 0...999)
                    HStack {
                        TextField("Course instructor", text: $instructor)
                            .textContentType(.name)
                        if !instructorSuggestions.isEmpty {
                            Menu {
                                ForEach(instructorSuggestions, id: \.self) { name in
                                    Button(name) { instructor = name }
                                }
                            } label: {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                            }
                            .accessibilityLabel("Suggested instructors")
                        }
                    }
                } footer: {
                    Text((number > 0
                          ? "Shows as \(AssignmentKind.display(kind: kind, number: number, title: title.trimmingCharacters(in: .whitespacesAndNewlines))). "
                          : "") + "A new subject added here has no classes until you put it in your timetable.")
                }

                Section {
                    DatePicker("Assigned on", selection: $assigned, displayedComponents: .date)
                    if customDue {
                        DatePicker("Due", selection: $due, in: assigned...)
                    } else {
                        LabeledContent("Due", value: AssignmentFormat.due(effectiveDue))
                    }
                    Toggle("Different deadline", isOn: $customDue.animation())
                } header: {
                    Text("Deadline")
                } footer: {
                    Text(customDue
                         ? "This one has its own due date."
                         : "Due \(deadlineDays) days after it was set, at the end of that day. Change the usual length in Settings → Assignments.")
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
            // On the Form, not a Section: Form rows load lazily, so a Section's onAppear
            // ran again whenever it scrolled back into view and reset a hand-set number.
            .onAppear {
                guard !didAppear else { return }
                didAppear = true
                renumber()
                recommendInstructor()
            }
            .onChange(of: kind) {
                renumber()
                recommendInstructor()
            }
            .onChange(of: subjectID) {
                renumber()
                recommendInstructor()
            }
            .onChange(of: customDue) { _, isCustom in
                if isCustom { due = Assignment.dueDate(assignedOn: assigned, days: deadlineDays) }
            }
            .onChange(of: assigned) {
                if customDue && due < assigned { due = Assignment.dueDate(assignedOn: assigned, days: deadlineDays) }
            }
            .sheet(isPresented: $showNewSubject) {
                SubjectFormView(subject: nil) { s in
                    if instructor.isEmpty || instructor == autoInstructor {
                        instructor = s.teacherName
                        autoInstructor = ""  // so the subject change below doesn't clear it
                    }
                    subjectID = s.id
                }
            }
            .navigationTitle(assignment == nil ? "New Assignment" : "Edit Assignment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && number == 0)
                }
            }
        }
    }

    /// New items only: an existing number is never changed behind your back.
    private func renumber() {
        guard assignment == nil, autoNumber else { return }
        number = Assignment.nextNumber(subjectID: subjectID, kind: kind, among: allAssignments)
    }

    /// Names used before for this subject and type, then the subject's teacher.
    private var instructorSuggestions: [String] {
        var names = Assignment.knownInstructors(subjectID: subjectID, kind: kind, among: allAssignments, excluding: assignment)
        if let teacher = subjects.first(where: { $0.id == subjectID })?.teacherName, !teacher.isEmpty,
           !names.contains(where: { $0.caseInsensitiveCompare(teacher) == .orderedSame }) {
            names.append(teacher)
        }
        return names
    }

    /// Fill in the best guess, unless you've typed a different name yourself.
    private func recommendInstructor() {
        let best = instructorSuggestions.first ?? ""
        if instructor.isEmpty || instructor == autoInstructor { instructor = best }
        autoInstructor = best
    }

    private func save() {
        let target = assignment ?? Assignment(title: "", dueDate: effectiveDue)
        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.kind = kind.rawValue
        target.number = number
        target.instructor = instructor.trimmingCharacters(in: .whitespacesAndNewlines)
        target.subjectID = subjectID
        target.assignedDate = Calendar.current.startOfDay(for: assigned)
        target.hasCustomDue = customDue
        target.dueDate = effectiveDue
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
                            Text(next.displayTitle)
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

// MARK: - Deadline bar

/// How much of the time to hand it in has gone: "Set Mon 26 Oct · 5 days left".
struct DeadlineBar: View {
    let assignment: Assignment
    let now: Date

    var body: some View {
        let start = Calendar.current.startOfDay(for: assignment.assignedDate)
        let total = max(assignment.dueDate.timeIntervalSince(start), 1)
        let used = min(max(now.timeIntervalSince(start) / total, 0), 1)
        let left = assignment.daysLeft(now: now)
        let leftText: String = {
            if assignment.dueDate < now { return "Past the deadline" }
            if left <= 0 { return "Last day" }
            return left == 1 ? "1 day left" : "\(left) days left"
        }()

        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Pastel.ink.opacity(0.12))
                    Capsule()
                        .fill(Pastel.ink.opacity(0.8))
                        .frame(width: max(6, geo.size.width * used))
                }
            }
            .frame(height: 6)
            Text("Set \(assignment.assignedDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))  ·  \(leftText)")
                .font(.caption2.weight(.semibold))
                .opacity(0.7)
        }
        .frame(maxWidth: 260, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
