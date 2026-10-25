import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var subjects: [Subject]
    @Query private var sessions: [AttendanceSession]

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
