import SwiftUI
import SwiftData
import Charts

/// Everything about one subject: its numbers, a month calendar of marks,
/// its weekly schedule, its trend and its most recent records.
struct SubjectDetailView: View {
    let subject: Subject

    @AppStorage(PrefKey.semesterEnabled) private var semesterEnabled = false
    @AppStorage(PrefKey.semesterStart) private var semesterStart = ""
    @AppStorage(PrefKey.semesterEnd) private var semesterEnd = ""

    @State private var month = Calendar.current.startOfMonth(for: Date())
    @State private var showEdit = false
    @State private var editing: AttendanceSession?

    private var semester: SemesterRange {
        SemesterRange(enabled: semesterEnabled, start: semesterStart, end: semesterEnd)
    }

    var body: some View {
        let sessions = subject.sessions.filter { semester.includes($0.sessionDate) }
        let summary = AttendanceCalculator.summary(
            statuses: sessions.flatMap { $0.units.map { $0.status } },
            target: subject.targetPercentage
        )
        let tint = Pastel.subject(subject.colorValue)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(summary, tint: tint)
                SubjectCalendar(month: $month, marks: dayMarks(subject.sessions))
                    .padding(18)
                    .tile(Pastel.surface, radius: 28)
                schedule
                trend(sessions, target: subject.targetPercentage)
                recent(subject.sessions)
            }
            .padding()
        }
        .background(Pastel.background)
        .navigationTitle(subject.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) { SubjectFormView(subject: subject) }
        .sheet(item: $editing) { SessionEditView(session: $0) }
    }

    // MARK: Header

    private func header(_ summary: AttendanceSummary, tint: Color) -> some View {
        let hasData = summary.conducted > 0
        let progress = hasData ? min(max(summary.percentage, 0), 100) / 100 : 0
        let goal = min(max(summary.target, 0), 100) / 100
        let meta = [subject.code, subject.type, subject.teacherName, subject.room]
            .filter { !$0.isEmpty }
            .joined(separator: "  ")

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subject.name)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    if !meta.isEmpty {
                        Text(meta).font(.caption.weight(.medium)).opacity(0.7)
                    }
                }
                Spacer()
                TilePill(text: attendanceLabel(summary))
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(hasData ? "\(Int(summary.percentage.rounded()))%" : "–")
                    .font(.system(size: 60, weight: .heavy, design: .rounded))
                Text("goal \(Int(summary.target.rounded()))%")
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.6)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Pastel.ink.opacity(0.12))
                    Capsule()
                        .fill(Pastel.ink)
                        .frame(width: max(12, geo.size.width * progress))
                    Capsule()
                        .fill(Pastel.surface)
                        .frame(width: 4, height: 20)
                        .overlay(Capsule().strokeBorder(Pastel.ink.opacity(0.5), lineWidth: 1))
                        .offset(x: geo.size.width * goal - 2)
                }
            }
            .frame(height: 12)

            HStack(spacing: 8) {
                chip(summary.present, "present", "checkmark")
                chip(summary.absent, "absent", "xmark")
                chip(summary.cancelled, "cancelled", "slash.circle")
            }

            Text(summary.message)
                .font(.subheadline)
                .opacity(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Pastel.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile(tint, radius: 32)
    }

    private func chip(_ value: Int, _ title: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.semibold))
                .opacity(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Pastel.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Weekly schedule

    @ViewBuilder
    private var schedule: some View {
        let entries = subject.timetableEntries
            .filter { $0.isActive }
            .sorted { ($0.dayOfWeek, $0.startTime) < ($1.dayOfWeek, $1.startTime) }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Every week")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                ForEach(entries) { entry in
                    HStack {
                        Text(Self.dayNames[max(0, min(6, entry.dayOfWeek - 1))])
                            .font(.subheadline.weight(.bold))
                            .frame(width: 44, alignment: .leading)
                        Text("\(DateUtils.displayTime(entry.startTime)) – \(DateUtils.displayTime(entry.endTime))")
                            .font(.subheadline)
                            .monospacedDigit()
                        Spacer()
                        let room = entry.roomOverride.isEmpty ? subject.room : entry.roomOverride
                        if !room.isEmpty {
                            Text(room).font(.caption).opacity(0.7)
                        }
                    }
                }
            }
            .foregroundStyle(Pastel.ink)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tile(Pastel.lavender, radius: 28)
        }
    }

    private static let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    // MARK: Trend

    @ViewBuilder
    private func trend(_ sessions: [AttendanceSession], target: Double) -> some View {
        let points = weeklyTrend(sessions)
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                Text("Trend")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Pastel.ink)
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("Week", point.week), y: .value("Attendance", point.percentage))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .foregroundStyle(Pastel.subjectStrong(subject.colorValue))
                    }
                    RuleMark(y: .value("Goal", target))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                        .foregroundStyle(Pastel.ink.opacity(0.5))
                }
                .chartYScale(domain: 0...100)
                .frame(height: 150)
            }
            .padding(18)
            .tile(Pastel.surface, radius: 28)
        }
    }

    private func weeklyTrend(_ sessions: [AttendanceSession]) -> [SubjectTrendPoint] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        var byWeek: [Date: (present: Int, conducted: Int)] = [:]
        for session in sessions {
            guard let day = DateUtils.date(fromISO: session.sessionDate),
                  let week = calendar.dateInterval(of: .weekOfYear, for: day)?.start else { continue }
            var count = byWeek[week] ?? (0, 0)
            for unit in session.units {
                switch unit.status {
                case .present: count.present += 1; count.conducted += 1
                case .absent, .bunked: count.conducted += 1
                default: break
                }
            }
            byWeek[week] = count
        }
        var present = 0, conducted = 0
        var points: [SubjectTrendPoint] = []
        for week in byWeek.keys.sorted() {
            present += byWeek[week]?.present ?? 0
            conducted += byWeek[week]?.conducted ?? 0
            if conducted > 0 { points.append(SubjectTrendPoint(week: week, percentage: Double(present) / Double(conducted) * 100)) }
        }
        return points
    }

    // MARK: Recent records

    @ViewBuilder
    private func recent(_ sessions: [AttendanceSession]) -> some View {
        let latest = sessions
            .sorted { ($0.sessionDate, $0.startTime) > ($1.sessionDate, $1.startTime) }
            .prefix(8)
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent classes")
                .font(.system(.headline, design: .rounded).weight(.bold))
            if latest.isEmpty {
                Text("No classes recorded yet.").font(.subheadline).opacity(0.7)
            }
            ForEach(Array(latest)) { session in
                Button { editing = session } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DateUtils.prettyDate(session.sessionDate)).font(.subheadline.weight(.semibold))
                            Text("\(DateUtils.displayTime(session.startTime)) – \(DateUtils.displayTime(session.endTime))")
                                .font(.caption)
                                .opacity(0.7)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            let count = max(session.expectedUnitCount, session.units.count)
                            ForEach(0..<count, id: \.self) { index in
                                let status = session.units.first(where: { $0.unitIndex == index })?.status ?? .unmarked
                                Text(status.label)
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(status == .unmarked ? Pastel.surface.opacity(0.7) : status.tint, in: Capsule())
                                    .foregroundStyle(status == .unmarked ? Pastel.ink : Color.white)
                            }
                        }
                    }
                    .padding(12)
                    .background(Pastel.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Pastel.ink)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile(Pastel.peach, radius: 28)
    }

    // MARK: Calendar data

    /// One summary mark per day for this subject.
    private func dayMarks(_ sessions: [AttendanceSession]) -> [String: DayMark] {
        var marks: [String: DayMark] = [:]
        for session in sessions {
            let statuses = session.units.map { $0.status }
            let mark: DayMark
            if statuses.contains(where: { $0 == .absent || $0 == .bunked }) {
                mark = statuses.contains(.present) ? .mixed : .absent
            } else if statuses.contains(.present) {
                mark = .present
            } else if statuses.contains(.cancelled) {
                mark = .cancelled
            } else {
                mark = .unmarked
            }
            marks[session.sessionDate] = (marks[session.sessionDate] ?? .unmarked).combined(with: mark)
        }
        return marks
    }
}

struct SubjectTrendPoint: Identifiable {
    let week: Date
    let percentage: Double
    var id: Date { week }
}

enum DayMark: Int {
    case unmarked = 0, cancelled, present, mixed, absent

    /// Worse news wins when one day has several classes.
    func combined(with other: DayMark) -> DayMark {
        DayMark(rawValue: max(rawValue, other.rawValue)) ?? self
    }

    var color: Color? {
        switch self {
        case .present: return DashboardPalette.green
        case .absent: return DashboardPalette.coral
        case .mixed: return DashboardPalette.amber
        case .cancelled: return DashboardPalette.blue
        case .unmarked: return nil
        }
    }
}

private struct SubjectCalendar: View {
    @Binding var month: Date
    let marks: [String: DayMark]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        let calendar = Calendar.current
        let days = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        // Monday-first offset for the 1st of the month.
        let leading = (calendar.component(.weekday, from: month) + 5) % 7
        let title = month.formatted(.dateTime.month(.wide).year())

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next month")
                    .padding(.leading, 12)
            }
            .foregroundStyle(Pastel.ink)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                    Text(["M", "T", "W", "T", "F", "S", "S"][i])
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Pastel.ink.opacity(0.5))
                }
                ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 34) }
                ForEach(1...days, id: \.self) { day in
                    let date = calendar.date(byAdding: .day, value: day - 1, to: month) ?? month
                    let mark = marks[DateUtils.isoString(date)] ?? .unmarked
                    let isToday = calendar.isDateInToday(date)
                    Text("\(day)")
                        .font(.footnote.weight(mark == .unmarked ? .regular : .bold))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(mark.color == nil ? Pastel.ink : Color.white)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(mark.color ?? Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Pastel.ink, lineWidth: isToday ? 1.5 : 0)
                        )
                }
            }

            HStack(spacing: 12) {
                legend("Present", DashboardPalette.green)
                legend("Absent", DashboardPalette.coral)
                legend("Mixed", DashboardPalette.amber)
                legend("Cancelled", DashboardPalette.blue)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(Pastel.ink.opacity(0.7))
        }
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
        }
    }

    private func shift(_ months: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: months, to: month) {
            withAnimation(.snappy) { month = next }
        }
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}
