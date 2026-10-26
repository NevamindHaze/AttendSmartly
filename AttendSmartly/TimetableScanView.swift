import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Pick a photo of a timetable, read it on the device, then review the suggested
/// classes before anything is saved.
struct TimetableScanView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Subject.name) private var subjects: [Subject]

    @State private var photoItem: PhotosPickerItem?
    @State private var stage: Stage = .pick
    @State private var rows: [ScanRow] = []
    @State private var errorText: String?

    enum Stage { case pick, reading, review }

    struct ScanRow: Identifiable {
        let id = UUID()
        var include = true
        var day: Int
        var start: Date
        var end: Date
        /// An existing subject, or nil to create a new one called `newName`.
        var subjectID: UUID?
        var newName: String
    }

    private static let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .pick: pickView
                case .reading: readingView
                case .review: reviewView
                }
            }
            .background(Pastel.background)
            .navigationTitle("Scan timetable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if stage == .review && !rows.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add \(rows.filter(\.include).count)") { save() }
                            .disabled(!rows.contains(where: \.include))
                    }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { @MainActor in await read(item) }
            }
            .alert("Couldn't read the photo", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    // MARK: Stages

    private var pickView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "text.viewfinder")
                        .font(.title2.weight(.bold))
                        .frame(width: 48, height: 48)
                        .background(Pastel.surface.opacity(0.75), in: Circle())
                    Text("Add classes from a photo")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text("Choose a clear, straight photo or screenshot of your timetable. The text is read on your iPhone, and you'll check every class before it's added.")
                        .font(.subheadline)
                        .opacity(0.8)
                }
                .foregroundStyle(Pastel.ink)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .tile(Pastel.sky, radius: 28)

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose a photo", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Pastel.ink, in: Capsule())
                        .foregroundStyle(Pastel.background)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Works best when").font(.subheadline.weight(.bold))
                    Text("• Days (Mon, Tue…) run down the side or across the top")
                    Text("• Times look like 9:00-10:00 or 2-4 pm")
                    Text("• The photo is taken straight on, with no glare")
                }
                .font(.footnote)
                .foregroundStyle(Pastel.ink.opacity(0.8))
                .padding(.horizontal, 4)
            }
            .padding()
        }
    }

    private var readingView: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Reading your timetable…").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var reviewView: some View {
        if rows.isEmpty {
            VStack(spacing: 16) {
                EmptyStateView(
                    symbol: "doc.text.magnifyingglass",
                    title: "No classes found",
                    message: "Try a sharper, straight-on photo, or crop it to just the timetable."
                )
                .tile(Pastel.surface)
                Button("Try another photo") {
                    photoItem = nil
                    stage = .pick
                }
                .font(.headline)
            }
            .padding()
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            List {
                Section {
                    Text("Found \(rows.count) classes. Check each one, fix anything that's off, and untick any you don't want.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach($rows) { $row in
                    Section {
                        Toggle(isOn: $row.include) {
                            Text(subjectTitle(row))
                                .font(.system(.headline, design: .rounded).weight(.bold))
                        }
                        if row.include {
                            Picker("Subject", selection: $row.subjectID) {
                                Text("New: \(row.newName)").tag(UUID?.none)
                                ForEach(subjects.filter { !$0.isArchived }) { subject in
                                    Text(subject.name).tag(Optional(subject.id))
                                }
                            }
                            if row.subjectID == nil {
                                TextField("New subject name", text: $row.newName)
                            }
                            Picker("Day", selection: $row.day) {
                                ForEach(1...7, id: \.self) { d in Text(Self.dayNames[d - 1]).tag(d) }
                            }
                            DatePicker("Starts", selection: $row.start, displayedComponents: .hourAndMinute)
                            DatePicker("Ends", selection: $row.end, displayedComponents: .hourAndMinute)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func subjectTitle(_ row: ScanRow) -> String {
        if let id = row.subjectID, let subject = subjects.first(where: { $0.id == id }) {
            return subject.name
        }
        return row.newName.isEmpty ? "New subject" : row.newName
    }

    // MARK: Reading

    @MainActor
    private func read(_ item: PhotosPickerItem) async {
        stage = .reading
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let cgImage = Self.uprightImage(image) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let texts = try await TimetableScanner.recognizeText(in: cgImage)
            let found = TimetableScanner.parse(texts)
            rows = found.map { item in
                ScanRow(
                    day: item.day,
                    start: DateUtils.time(from: item.start),
                    end: DateUtils.time(from: item.end),
                    subjectID: matchSubject(item.name)?.id,
                    newName: item.name
                )
            }
            stage = .review
        } catch {
            errorText = "Try a different photo. (\(error.localizedDescription))"
            stage = .pick
        }
        photoItem = nil
    }

    /// Redraws the photo the right way up and no bigger than 3000 px, so text reads well.
    private static func uprightImage(_ image: UIImage) -> CGImage? {
        let maxSide: CGFloat = 3000
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.cgImage
    }

    /// Finds an existing subject with the same or a very similar name.
    private func matchSubject(_ name: String) -> Subject? {
        let target = normalise(name)
        guard !target.isEmpty else { return nil }
        let candidates = subjects.filter { !$0.isArchived }
        if let exact = candidates.first(where: { normalise($0.name) == target || normalise($0.code) == target }) {
            return exact
        }
        return candidates.first { subject in
            let n = normalise(subject.name)
            return n.count >= 3 && target.count >= 3 && (n.contains(target) || target.contains(n))
        }
    }

    private func normalise(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: Saving

    private func save() {
        var created: [String: Subject] = [:]
        for row in rows where row.include {
            let subject: Subject
            if let id = row.subjectID, let existing = subjects.first(where: { $0.id == id }) {
                subject = existing
            } else {
                let name = row.newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                if let made = created[name.lowercased()] {
                    subject = made
                } else {
                    let made = Subject(name: name)
                    context.insert(made)
                    created[name.lowercased()] = made
                    subject = made
                }
            }

            let start = DateUtils.hhmm(row.start)
            let end = DateUtils.hhmm(row.end)
            guard end > start else { continue }
            let duplicate = subject.timetableEntries.contains {
                $0.dayOfWeek == row.day && $0.startTime == start && $0.endTime == end
            }
            guard !duplicate else { continue }

            let entry = TimetableEntry()
            entry.dayOfWeek = row.day
            entry.startTime = start
            entry.endTime = end
            let minutes = Calendar.current.dateComponents([.minute], from: row.start, to: row.end).minute ?? 60
            let unitLength = max(subject.attendanceUnitMinutes, 1)
            entry.attendanceUnitCount = max(1, Int((Double(minutes) / Double(unitLength)).rounded()))
            context.insert(entry)
            entry.subject = subject
        }
        do {
            try context.save()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
