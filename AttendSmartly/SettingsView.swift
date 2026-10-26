import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var subjects: [Subject]
    @Query private var sessions: [AttendanceSession]

    @AppStorage(PrefKey.semesterEnabled) private var semesterEnabled = false
    @AppStorage(PrefKey.semesterStart) private var semesterStart = ""
    @AppStorage(PrefKey.semesterEnd) private var semesterEnd = ""
    @AppStorage(PrefKey.remindersEnabled) private var remindersEnabled = false
    @AppStorage(PrefKey.assignmentRemindersEnabled) private var assignmentRemindersEnabled = true
    @AppStorage(PrefKey.assignmentDeadlineDays) private var assignmentDeadlineDays = 7
    @AppStorage(PrefKey.userName) private var userName = "Marshal"
    @AppStorage(PrefKey.profilePhotoVersion) private var photoVersion = 0

    @State private var photoItem: PhotosPickerItem?
    @AppStorage(PrefKey.autoBackupEnabled) private var autoBackupEnabled = true
    @AppStorage(PrefKey.lastAutoBackup) private var lastAutoBackup: Double = 0

    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportDocument = BackupDocument(data: Data())
    @State private var pendingImport: Data?
    @State private var message: String?
    @State private var confirmDeleteAll = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    HStack(spacing: 16) {
                        AvatarView(size: 72)
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Your name", text: $userName)
                                .font(.headline)
                                .textInputAutocapitalization(.words)
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label(hasPhoto ? "Change photo" : "Add a photo", systemImage: "photo.on.rectangle")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.borderless)
                            if hasPhoto {
                                Button(role: .destructive) {
                                    ProfileStore.remove()
                                    photoVersion += 1
                                } label: {
                                    Label("Remove photo", systemImage: "trash")
                                        .font(.subheadline)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Your data") {
                    LabeledContent("Subjects", value: "\(subjects.count)")
                    LabeledContent("Attendance sessions", value: "\(sessions.count)")
                    NavigationLink {
                        HolidaysView()
                    } label: {
                        Label("Holidays", systemImage: "party.popper")
                    }
                }

                Section {
                    Toggle("Class reminders", isOn: $remindersEnabled)
                    Toggle("Assignment reminders", isOn: $assignmentRemindersEnabled)
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Class reminders arrive before each timetable class (10 minutes by default). Assignment reminders arrive at 6 PM the day before, 9 AM on the due day, and an hour before it's due.")
                }

                Section {
                    Stepper(
                        "Deadline: \(assignmentDeadlineDays) \(assignmentDeadlineDays == 1 ? "day" : "days")",
                        value: $assignmentDeadlineDays,
                        in: 1...60
                    )
                } header: {
                    Text("Assignments")
                } footer: {
                    Text("New assignments are due this many days after they're set, at the end of that day. You can still give any assignment its own due date.")
                }

                Section {
                    Toggle("Track by semester", isOn: $semesterEnabled)
                    if semesterEnabled {
                        Toggle("Start date", isOn: dateEnabled($semesterStart))
                        if !semesterStart.isEmpty {
                            DatePicker("From", selection: dateBinding($semesterStart), displayedComponents: .date)
                        }
                        Toggle("End date", isOn: dateEnabled($semesterEnd))
                        if !semesterEnd.isEmpty {
                            DatePicker("Until", selection: dateBinding($semesterEnd), displayedComponents: .date)
                        }
                    }
                } header: {
                    Text("Semester")
                } footer: {
                    Text("Only classes inside this date range count towards attendance on Home, Subjects and Analytics.")
                }

                Section {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import backup (.json)", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        exportBackup()
                    } label: {
                        Label("Export backup (.json)", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Works with backups exported from the Android app, and exports in the same format.")
                }

                Section {
                    Toggle("Weekly automatic backup", isOn: $autoBackupEnabled)
                    LabeledContent("Last backup", value: lastAutoBackup > 0
                        ? Date(timeIntervalSince1970: lastAutoBackup).formatted(date: .abbreviated, time: .shortened)
                        : "Not yet")
                    Button {
                        do {
                            try AutoBackup.runNow(context)
                            message = "Backup saved. Find it in the Files app under On My iPhone > AttendSmartly > Backups."
                        } catch {
                            message = "Couldn't save the backup: \(error.localizedDescription)"
                        }
                    } label: {
                        Label("Back up now", systemImage: "externaldrive.badge.checkmark")
                    }
                } header: {
                    Text("Automatic backup")
                } footer: {
                    Text("Saved once a week to Files > On My iPhone > AttendSmartly > Backups. The newest \(AutoBackup.keep) are kept. These live inside the app, so copy one to iCloud Drive now and then: deleting the app deletes them too.")
                }

                Section {
                    Button(role: .destructive) {
                        confirmDeleteAll = true
                    } label: {
                        Label("Delete all data", systemImage: "trash")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Pastel.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { @MainActor in
                    do {
                        if let data = try await item.loadTransferable(type: Data.self) {
                            try ProfileStore.save(data)
                            photoVersion += 1
                        }
                    } catch {
                        message = "Couldn't use that photo. Try a different one."
                    }
                    photoItem = nil
                }
            }
            .onChange(of: assignmentRemindersEnabled) { _, isOn in
                guard isOn else { return }
                Task { @MainActor in
                    let granted = await ReminderService.requestAuthorization()
                    if !granted {
                        assignmentRemindersEnabled = false
                        message = "Notifications are turned off for AttendSmartly. Enable them in iOS Settings → Notifications, then try again."
                    }
                }
            }
            .onChange(of: remindersEnabled) { _, isOn in
                guard isOn else { return }
                Task { @MainActor in
                    let granted = await ReminderService.requestAuthorization()
                    if !granted {
                        remindersEnabled = false
                        message = "Notifications are turned off for AttendSmartly. Enable them in iOS Settings → Notifications, then try again."
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .plainText]) { result in
                handlePicked(result)
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "AttendSmartly_backup"
            ) { result in
                if case .failure(let error) = result { message = error.localizedDescription }
            }
            .alert("Replace existing data?", isPresented: Binding(
                get: { pendingImport != nil },
                set: { if !$0 { pendingImport = nil } }
            )) {
                Button("Replace", role: .destructive) { runImport(replace: true) }
                Button("Merge (keep current data)") { runImport(replace: false) }
                Button("Cancel", role: .cancel) { pendingImport = nil }
            } message: {
                Text("Replace deletes everything currently in the app first. Merge adds the backup alongside it.")
            }
            .alert("Delete all data?", isPresented: $confirmDeleteAll) {
                Button("Delete everything", role: .destructive) {
                    do { try BackupService.wipe(context) } catch { message = error.localizedDescription }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes every subject, timetable entry and attendance record. Export a backup first if unsure.")
            }
            .alert("Backup", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var hasPhoto: Bool {
        photoVersion >= 0 && ProfileStore.load() != nil
    }

    // MARK: Semester date helpers (stored as yyyy-MM-dd strings; empty = not set)

    private func dateEnabled(_ value: Binding<String>) -> Binding<Bool> {
        Binding(
            get: { !value.wrappedValue.isEmpty },
            set: { on in value.wrappedValue = on ? DateUtils.isoString(Date()) : "" }
        )
    }

    private func dateBinding(_ value: Binding<String>) -> Binding<Date> {
        Binding(
            get: { DateUtils.date(fromISO: value.wrappedValue) ?? Date() },
            set: { value.wrappedValue = DateUtils.isoString($0) }
        )
    }

    // MARK: Backup

    private func handlePicked(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            message = error.localizedDescription
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                pendingImport = try Data(contentsOf: url)
            } catch {
                message = "Couldn't read the file: \(error.localizedDescription)"
            }
        }
    }

    private func runImport(replace: Bool) {
        guard let data = pendingImport else { return }
        pendingImport = nil
        do {
            let result = try BackupService.importData(data, into: context, replaceExisting: replace)
            message = result.summary
        } catch {
            message = error.localizedDescription
        }
    }

    private func exportBackup() {
        do {
            exportDocument = BackupDocument(data: try BackupService.exportData(from: context))
            showExporter = true
        } catch {
            message = error.localizedDescription
        }
    }
}
