import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var subjects: [Subject]
    @Query private var sessions: [AttendanceSession]

    @AppStorage(PrefKey.semesterEnabled) private var semesterEnabled = false
    @AppStorage(PrefKey.semesterStart) private var semesterStart = ""
    @AppStorage(PrefKey.semesterEnd) private var semesterEnd = ""
    @AppStorage(PrefKey.remindersEnabled) private var remindersEnabled = false

    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportDocument = BackupDocument(data: Data())
    @State private var pendingImport: Data?
    @State private var message: String?
    @State private var confirmDeleteAll = false

    var body: some View {
        NavigationStack {
            Form {
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
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("A weekly notification before each timetable class, using that class's reminder time (10 minutes by default).")
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
                    Button(role: .destructive) {
                        confirmDeleteAll = true
                    } label: {
                        Label("Delete all data", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
