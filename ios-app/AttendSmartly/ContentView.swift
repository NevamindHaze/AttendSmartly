import SwiftUI
import SwiftData

// MARK: - Shared helpers

enum DashboardPalette {
    static let green = Color(red: 0.12, green: 0.42, blue: 0.34)
    static let blue = Color(red: 0.26, green: 0.48, blue: 0.72)
    static let coral = Color(red: 0.82, green: 0.38, blue: 0.29)
}

extension Color {
    /// Android stores colours as 0xAARRGGBB integers.
    init(argb: Int) {
        let v = UInt32(truncatingIfNeeded: argb)
        self.init(
            .sRGB,
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum DateUtils {
    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func isoString(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    static func date(fromISO iso: String) -> Date? {
        isoFormatter.date(from: iso)
    }

    /// "2026-10-26" -> "Mon, 26 Oct 2026"
    static func prettyDate(_ iso: String) -> String {
        guard let d = isoFormatter.date(from: iso) else { return iso }
        let f = DateFormatter()
        f.dateFormat = "EEE, d MMM yyyy"
        return f.string(from: d)
    }

    /// "13:30" -> a Date today at 13:30 (for DatePicker)
    static func time(from hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":")
        let h = Int(parts.first ?? "9") ?? 9
        let m = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
    }

    static func hhmm(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// 1 = Monday ... 7 = Sunday, matching the Android app.
    static func dayOfWeek(_ date: Date) -> Int {
        let w = Calendar.current.component(.weekday, from: date) // Sunday = 1
        return (w + 5) % 7 + 1
    }

    static func longDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM yyyy"
        return f.string(from: date)
    }

    /// "13:30" -> "1:30 PM"
    static func displayTime(_ hhmm: String) -> String {
        let parts = hhmm.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return hhmm }
        let suffix = h >= 12 ? "PM" : "AM"
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12):\(String(format: "%02d", m)) \(suffix)"
    }

    /// Returns whether a recurring timetable entry is active on a specific calendar date.
    /// ISO dates are fixed-width yyyy-MM-dd strings, so lexical comparison is chronological.
    static func isScheduled(_ entry: TimetableEntry, on date: Date) -> Bool {
        let dateISO = isoString(date)
        guard entry.isActive, entry.dayOfWeek == dayOfWeek(date) else { return false }
        guard entry.startDate.isEmpty || entry.startDate <= dateISO else { return false }
        guard entry.endDate.isEmpty || entry.endDate >= dateISO else { return false }
        return true
    }

    /// Resolves a Monday-first weekday selection to its date in the current week.
    static func date(forDayOfWeek day: Int, inWeekContaining date: Date) -> Date {
        let calendar = Calendar.current
        let startOfDate = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: day - dayOfWeek(date), to: startOfDate) ?? startOfDate
    }
}

// MARK: - Root

struct ContentView: View {
    @Query private var entries: [TimetableEntry]
    @AppStorage(PrefKey.remindersEnabled) private var remindersEnabled = false

    /// Changes whenever anything that affects reminders changes.
    private var reminderSignature: String {
        var parts: [String] = []
        for e in entries where e.isActive {
            guard let subject = e.subject else { continue }
            var key = e.id.uuidString
            key += "|\(e.dayOfWeek)|\(e.startTime)|\(e.reminderMinutes)"
            key += "|\(subject.name)|\(subject.isArchived)|\(e.roomOverride)"
            parts.append(key)
        }
        parts.sort()
        return "\(remindersEnabled)#" + parts.joined(separator: ";")
    }

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            SubjectsView()
                .tabItem { Label("Subjects", systemImage: "book.closed") }

            TimetableView()
                .tabItem { Label("Timetable", systemImage: "calendar") }

            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            AnalyticsView()
                .tabItem { Label("Analytics", systemImage: "chart.bar.xaxis") }
        }
        .tint(DashboardPalette.green)
        .task(id: reminderSignature) { @MainActor in
            let items = ReminderService.items(from: entries)
            await ReminderService.reschedule(items: items, enabled: remindersEnabled)
        }
    }

    private func placeholder(_ title: String, symbol: String, message: String) -> some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(DashboardPalette.green)
                Text(title).font(.title3.bold())
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .navigationTitle(title)
        }
    }
}
