import Foundation

// Shared by the app and the widget extension. Keep this file free of app-only types.

/// A small, self-contained copy of what the widget needs, written by the app
/// into the shared App Group folder whenever the app goes to the background.
struct WidgetSnapshot: Codable {
    struct ClassItem: Codable, Hashable {
        /// 1 = Monday ... 7 = Sunday, for weekly timetable classes.
        var weekday: Int?
        /// yyyy-MM-dd, for one-off extra or rescheduled classes.
        var date: String?
        var startTime: String
        var endTime: String
        var name: String
        var room: String
        var colorARGB: Int
        var startDate: String
        var endDate: String
    }

    var generatedAt: Date
    var userName: String
    var percentage: Double
    var target: Double
    var present: Int
    var conducted: Int
    var message: String
    var classes: [ClassItem]
    /// Dates (yyyy-MM-dd) mapped to the holiday's title.
    var holidays: [String: String]
    /// Weekly classes cancelled or moved on a specific date: "yyyy-MM-dd|HH:mm|name".
    var skipped: [String]

    /// The classes happening on a given day, in start-time order.
    func classes(on date: Date, calendar: Calendar = .current) -> [ClassItem] {
        let iso = WidgetSnapshot.iso(date)
        if holidays[iso] != nil { return [] }
        let weekday = (calendar.component(.weekday, from: date) + 5) % 7 + 1
        return classes
            .filter { item in
                if let date = item.date { return date == iso }
                guard item.weekday == weekday else { return false }
                if !item.startDate.isEmpty && item.startDate > iso { return false }
                if !item.endDate.isEmpty && item.endDate < iso { return false }
                return !skipped.contains("\(iso)|\(item.startTime)|\(item.name)")
            }
            .sorted { $0.startTime < $1.startTime }
    }

    static func iso(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// Finds the folder shared between the app and the widget.
///
/// SideStore and AltStore rename App Groups when they sign the app (adding the
/// signer's team ID) and list the real names under `ALTAppGroups` in Info.plist,
/// so those names are tried first, then the original one.
enum AppGroup {
    static let defaultIdentifier = "group.com.agupta07505.attendsmartly"

    static var identifiers: [String] {
        var ids: [String] = []
        let bundles = [Bundle.main, containingAppBundle].compactMap { $0 }
        for bundle in bundles {
            if let groups = bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
                ids.append(contentsOf: groups)
            }
        }
        ids.append(defaultIdentifier)
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    /// For the widget: the app bundle that contains it (App.app/PlugIns/Widget.appex).
    private static var containingAppBundle: Bundle? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "appex" else { return nil }
        return Bundle(url: url.deletingLastPathComponent().deletingLastPathComponent())
    }

    static var containerURL: URL? {
        for id in identifiers {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
                return url
            }
        }
        return nil
    }

    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent("widget-snapshot.json")
    }

    static func loadSnapshot() -> WidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    static func save(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = snapshotURL else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(snapshot) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
