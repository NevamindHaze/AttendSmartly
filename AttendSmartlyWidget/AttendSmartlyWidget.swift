import SwiftUI
import WidgetKit

// MARK: - Timeline

struct AttendanceEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct AttendanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> AttendanceEntry {
        AttendanceEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (AttendanceEntry) -> Void) {
        let snapshot = AppGroup.loadSnapshot() ?? (context.isPreview ? .sample : nil)
        completion(AttendanceEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AttendanceEntry>) -> Void) {
        let now = Date()
        let snapshot = AppGroup.loadSnapshot()
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now

        // A new entry whenever a class ends, so "Next" moves along through the day.
        var dates: [Date] = [now]
        for item in snapshot?.classes(on: now) ?? [] {
            if let end = classTime(item.endTime, on: now), end > now { dates.append(end) }
        }
        let entries = Set(dates).sorted().map { AttendanceEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}

func classTime(_ hhmm: String, on day: Date) -> Date? {
    let parts = hhmm.split(separator: ":")
    guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
    return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: day)
}

func displayTime(_ hhmm: String) -> String {
    let parts = hhmm.split(separator: ":")
    guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return hhmm }
    let h12 = h % 12 == 0 ? 12 : h % 12
    return "\(h12):\(String(format: "%02d", m)) \(h >= 12 ? "PM" : "AM")"
}

extension WidgetSnapshot {
    static let sample = WidgetSnapshot(
        generatedAt: Date(),
        userName: "Marshal",
        percentage: 82,
        target: 75,
        present: 41,
        conducted: 50,
        message: "You can safely miss 4 units and stay above 75%.",
        classes: [
            .init(weekday: (Calendar.current.component(.weekday, from: Date()) + 5) % 7 + 1, date: nil,
                  startTime: "11:00", endTime: "13:00", name: "Surgery Lab", room: "Block B",
                  colorARGB: 0xFF2196F3, startDate: "", endDate: ""),
        ],
        holidays: [:],
        skipped: []
    )

    /// 0 = no data, 1 = below target, 2 = close, 3 = on track.
    var level: Int {
        if conducted == 0 { return 0 }
        let margin = percentage - target
        if margin < 0 { return 1 }
        if margin <= 5 { return 2 }
        return 3
    }

    var levelText: String {
        ["No classes yet", "Below target", "Close to target", "On track"][level]
    }

    func nextClass(after date: Date) -> ClassItem? {
        classes(on: date).first { item in
            guard let end = classTime(item.endTime, on: date) else { return false }
            return end > date
        }
    }
}

// MARK: - Colours (same pastel family as the app)

struct WidgetPalette {
    let scheme: ColorScheme

    private func pick(_ light: UInt32, _ dark: UInt32) -> Color {
        let hex = scheme == .dark ? dark : light
        return Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    var ink: Color { pick(0x22192F, 0xF5F1FB) }
    var surface: Color { pick(0xFFFFFF, 0x221F2B) }

    func tile(_ level: Int) -> Color {
        switch level {
        case 1: return pick(0xF9CFDD, 0x4C2536)
        case 2: return pick(0xFBE6A2, 0x47391A)
        case 3: return pick(0xC5EBD7, 0x1D4133)
        default: return pick(0xDDD3F8, 0x312A54)
        }
    }

    static func subject(_ argb: Int) -> Color {
        let v = UInt32(truncatingIfNeeded: argb)
        return Color(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}

// MARK: - Views

struct AttendanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: AttendanceEntry

    var body: some View {
        let palette = WidgetPalette(scheme: scheme)
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .systemSmall: small(snapshot, palette)
                case .systemMedium: medium(snapshot, palette)
                case .accessoryCircular: circular(snapshot)
                case .accessoryRectangular: rectangular(snapshot)
                case .accessoryInline: inline(snapshot)
                default: small(snapshot, palette)
                }
            } else {
                setup(palette)
            }
        }
        .containerBackground(for: .widget) {
            switch family {
            case .accessoryCircular, .accessoryRectangular, .accessoryInline:
                Color.clear
            default:
                palette.tile(entry.snapshot?.level ?? 0)
            }
        }
    }

    private func percentText(_ s: WidgetSnapshot) -> String {
        s.conducted == 0 ? "–" : "\(Int(s.percentage.rounded()))%"
    }

    private func small(_ s: WidgetSnapshot, _ p: WidgetPalette) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s.levelText)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(p.surface.opacity(0.7), in: Capsule())
            Spacer(minLength: 0)
            Text(percentText(s))
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.6)
            Text("goal \(Int(s.target.rounded()))%")
                .font(.caption2.weight(.semibold))
                .opacity(0.65)
            Spacer(minLength: 0)
            if let next = s.nextClass(after: entry.date) {
                Text("Next: \(next.name)")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Text(displayTime(next.startTime))
                    .font(.caption2)
                    .opacity(0.7)
            } else {
                Text("No more classes today")
                    .font(.caption2.weight(.semibold))
                    .opacity(0.7)
            }
        }
        .foregroundStyle(p.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ s: WidgetSnapshot, _ p: WidgetPalette) -> some View {
        let today = s.classes(on: entry.date)
        let holiday = s.holidays[WidgetSnapshot.iso(entry.date)]
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(s.levelText)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(p.surface.opacity(0.7), in: Capsule())
                Spacer(minLength: 0)
                Text(percentText(s))
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6)
                Text("\(s.present) of \(s.conducted) attended")
                    .font(.caption2.weight(.semibold))
                    .opacity(0.65)
            }
            .frame(maxWidth: 120, maxHeight: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("Today")
                    .font(.caption.weight(.bold))
                if let holiday {
                    Text(holiday).font(.caption).opacity(0.75)
                } else if today.isEmpty {
                    Text("No classes").font(.caption).opacity(0.75)
                } else {
                    ForEach(today.prefix(3), id: \.self) { item in
                        let past = (classTime(item.endTime, on: entry.date) ?? entry.date) <= entry.date
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(WidgetPalette.subject(item.colorARGB))
                                .frame(width: 4, height: 24)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(displayTime(item.startTime))
                                    .font(.caption2)
                                    .opacity(0.7)
                            }
                        }
                        .opacity(past ? 0.45 : 1)
                    }
                    if today.count > 3 {
                        Text("+\(today.count - 3) more").font(.caption2).opacity(0.7)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(p.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .foregroundStyle(p.ink)
    }

    private func circular(_ s: WidgetSnapshot) -> some View {
        Gauge(value: min(max(s.percentage, 0), 100), in: 0...100) {
            Text("Attendance")
        } currentValueLabel: {
            Text(s.conducted == 0 ? "–" : "\(Int(s.percentage.rounded()))")
                .font(.system(.body, design: .rounded).weight(.bold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    private func rectangular(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(percentText(s)) attendance")
                .font(.headline)
                .widgetAccentable()
            if let next = s.nextClass(after: entry.date) {
                Text(next.name).font(.caption).lineLimit(1)
                Text(displayTime(next.startTime) + (next.room.isEmpty ? "" : "  \(next.room)"))
                    .font(.caption2)
                    .lineLimit(1)
            } else {
                Text("No more classes today").font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ s: WidgetSnapshot) -> some View {
        if let next = s.nextClass(after: entry.date) {
            Text("\(percentText(s)) · \(next.name) \(displayTime(next.startTime))")
        } else {
            Text("\(percentText(s)) attendance")
        }
    }

    private func setup(_ p: WidgetPalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "checklist")
                .font(.title3.weight(.bold))
            Text("Open AttendSmartly once to set up this widget.")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(p.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Widget

struct AttendanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AttendanceWidget", provider: AttendanceProvider()) { entry in
            AttendanceWidgetView(entry: entry)
        }
        .configurationDisplayName("Attendance")
        .description("Your attendance and today's classes.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

@main
struct AttendSmartlyWidgetBundle: WidgetBundle {
    var body: some Widget {
        AttendanceWidget()
    }
}
