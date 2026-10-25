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
}

// MARK: - Root

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            SubjectsView()
                .tabItem { Label("Subjects", systemImage: "book.closed") }

            placeholder("Timetable", symbol: "calendar", message: "Timetable editing is coming in the next update. Import a backup from Settings to see your classes on Home.")
                .tabItem { Label("Timetable", systemImage: "calendar") }

            placeholder("History", symbol: "clock.arrow.circlepath", message: "Attendance history is coming in the next update.")
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            placeholder("Analytics", symbol: "chart.bar.xaxis", message: "Analytics are coming in a later update.")
                .tabItem { Label("Analytics", systemImage: "chart.bar.xaxis") }
        }
        .tint(DashboardPalette.green)
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
