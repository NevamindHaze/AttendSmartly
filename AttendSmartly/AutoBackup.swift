import Foundation
import SwiftData

extension PrefKey {
    static let autoBackupEnabled = "autoBackupEnabled"
    static let lastAutoBackup = "lastAutoBackup"
}

/// Saves a backup once a week into the app's Documents/Backups folder, which shows up in
/// the Files app under On My iPhone > AttendSmartly > Backups. Keeps the newest few.
enum AutoBackup {
    static let keep = 8
    static let interval: TimeInterval = 7 * 24 * 60 * 60

    static var folder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Backups", isDirectory: true)
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: PrefKey.autoBackupEnabled) as? Bool ?? true
    }

    static var lastBackup: Date? {
        let value = UserDefaults.standard.double(forKey: PrefKey.lastAutoBackup)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    /// Makes a backup if automatic backups are on and the last one is a week old.
    @MainActor
    static func runIfDue(_ context: ModelContext, now: Date = Date()) {
        guard isEnabled else { return }
        if let last = lastBackup, now.timeIntervalSince(last) < interval { return }
        // Nothing worth saving yet on a fresh install.
        let subjectCount = (try? context.fetchCount(FetchDescriptor<Subject>())) ?? 0
        guard subjectCount > 0 else { return }
        _ = try? runNow(context, now: now)
    }

    /// Writes a backup right away and returns where it was saved.
    @MainActor
    @discardableResult
    static func runNow(_ context: ModelContext, now: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let url = folder.appendingPathComponent("AttendSmartly_\(formatter.string(from: now)).json")
        let data = try BackupService.exportData(from: context)
        try data.write(to: url, options: .atomic)
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: PrefKey.lastAutoBackup)
        prune()
        return url
    }

    /// Removes all but the newest `keep` backups.
    static func prune() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )) ?? []
        let backups = files
            .filter { $0.lastPathComponent.hasPrefix("AttendSmartly_") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in backups.dropFirst(keep) {
            try? FileManager.default.removeItem(at: old)
        }
    }
}
