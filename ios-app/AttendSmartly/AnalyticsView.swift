import SwiftUI
import SwiftData
import Charts

private struct SubjectStat: Identifiable {
    let id: UUID
    let subject: Subject
    let summary: AttendanceSummary
}

private struct WeekCount {
    var present = 0
    var conducted = 0
}

private struct TrendPoint: Identifiable {
    let id = UUID()
    let week: Date
    let percentage: Double
}

struct AnalyticsView: View {
    @Query private var subjects: [Subject]
    @Query private var allSessions: [AttendanceSession]

    @AppStorage(PrefKey.semesterEnabled) private var semesterEnabled = false
    @AppStorage(PrefKey.semesterStart) private var semesterStart = ""
    @AppStorage(PrefKey.semesterEnd) private var semesterEnd = ""

    var body: some View {
        let semester = SemesterRange(enabled: semesterEnabled, start: semesterStart, end: semesterEnd)
        let sessions = allSessions.filter { semester.includes($0.sessionDate) }
        let active = subjects.filter { !$0.isArchived }
        let allStatuses = sessions.flatMap { s -> [AttendanceStatus] in
            guard let subject = s.subject, !subject.isArchived else { return [] }
            return s.units.map { $0.status }
        }
        let target = active.isEmpty ? 75 : active.map { $0.targetPercentage }.reduce(0, +) / Double(active.count)
        let overall = AttendanceCalculator.summary(statuses: allStatuses, target: target)

        let stats: [SubjectStat] = active.map { subject in
            let statuses = subject.sessions
                .filter { semester.includes($0.sessionDate) }
                .flatMap { $0.units.map { $0.status } }
            return SubjectStat(
                id: subject.id,
                subject: subject,
                summary: AttendanceCalculator.summary(statuses: statuses, target: subject.targetPercentage)
            )
        }
        let tracked = stats.filter { $0.summary.conducted > 0 }
        let below = tracked.filter { $0.summary.percentage < $0.summary.target }
            .sorted { $0.summary.percentage < $1.summary.percentage }
        let near = tracked.filter {
            let diff = $0.summary.percentage - $0.summary.target
            return diff >= 0 && diff <= 5
        }
        // Ties are broken the same way every time: more classes attended, then name.
        let ranked = tracked.sorted {
            if $0.summary.percentage != $1.summary.percentage { return $0.summary.percentage > $1.summary.percentage }
            if $0.summary.present != $1.summary.present { return $0.summary.present > $1.summary.present }
            return $0.subject.name.localizedCaseInsensitiveCompare($1.subject.name) == .orderedAscending
        }
        let best = ranked.first
        let lowest = ranked.count > 1 ? ranked.last : nil
        let totalSafe = tracked.map { $0.summary.safeBunks }.reduce(0, +)
        let trend = weeklyTrend(sessions)

        NavigationStack {
            ScrollView {
                if tracked.isEmpty {
                    EmptyStateView(
                        symbol: "chart.bar.xaxis",
                        title: "Nothing to analyse yet",
                        message: "Mark some classes or import a backup and your insights will show up here."
                    )
                    .tile(Pastel.surface)
                    .padding()
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        overallCard(overall, statuses: allStatuses)
                        HStack(spacing: 12) {
                            if let best {
                                highlightTile("Best", best, symbol: "trophy.fill", color: Pastel.mint)
                            }
                            if let lowest {
                                highlightTile("Needs work", lowest, symbol: "flame.fill", color: Pastel.pink)
                            }
                        }
                        safeBunksTile(totalSafe)
                        ranking(ranked)
                        subjectChart(tracked)
                        if trend.count >= 2 { trendChart(trend, target: target) }
                        attention(title: "Below target", systemImage: "exclamationmark.triangle.fill",
                                  color: Pastel.pink, items: below)
                        attention(title: "Close to target", systemImage: "eye.fill",
                                  color: Pastel.butter, items: near)
                    }
                    .padding()
                }
            }
            .background(Pastel.background)
            .navigationTitle("Analytics")
        }
    }

    // MARK: Sections

    private func card<Content: View>(_ color: Color, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tile(color, radius: 28)
    }

    private func heading(_ title: String, _ subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Pastel.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Pastel.ink.opacity(0.65))
            }
        }
    }

    private func overallCard(_ overall: AttendanceSummary, statuses: [AttendanceStatus]) -> some View {
        func count(_ s: AttendanceStatus) -> Int { statuses.filter { $0 == s }.count }

        return card(Pastel.status(overall)) {
            HStack {
                heading("Overall attendance")
                Spacer()
                TilePill(text: attendanceLabel(overall))
            }
            HStack(spacing: 22) {
                ProgressRing(value: overall.percentage, target: overall.target, tint: Pastel.ink, lineWidth: 14) {
                    VStack(spacing: 0) {
                        Text("\(Int(overall.percentage.rounded()))%")
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .foregroundStyle(Pastel.ink)
                        Text("goal \(Int(overall.target.rounded()))%")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Pastel.ink.opacity(0.6))
                    }
                }
                .frame(width: 140, height: 140)

                VStack(alignment: .leading, spacing: 9) {
                    countRow("Present", count(.present), "checkmark")
                    countRow("Absent", count(.absent), "xmark")
                    if count(.bunked) > 0 {
                        countRow("Bunked", count(.bunked), "figure.walk")
                    }
                    countRow("Cancelled", count(.cancelled), "slash.circle")
                }
            }
            Text(overall.message)
                .font(.subheadline)
                .foregroundStyle(Pastel.ink.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func countRow(_ title: String, _ value: Int, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .frame(width: 24, height: 24)
                .background(Pastel.surface.opacity(0.7), in: Circle())
            Text("\(value)")
                .font(.system(.body, design: .rounded).weight(.bold))
                .monospacedDigit()
            Text(title)
                .font(.subheadline)
                .opacity(0.7)
        }
        .foregroundStyle(Pastel.ink)
    }

    private func highlightTile(_ title: String, _ stat: SubjectStat, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.bold))
                    .frame(width: 34, height: 34)
                    .background(Pastel.surface.opacity(0.75), in: Circle())
                Spacer()
                Text(title)
                    .font(.caption.weight(.semibold))
                    .opacity(0.7)
            }
            Text("\(Int(stat.summary.percentage.rounded()))%")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .monospacedDigit()
            Text(stat.subject.name)
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Pastel.ink)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tile(color, radius: 26)
    }

    private func safeBunksTile(_ total: Int) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.subheadline.weight(.bold))
                .frame(width: 38, height: 38)
                .background(Pastel.surface.opacity(0.75), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("Safe to miss").font(.subheadline.weight(.semibold))
                Text("Classes you can skip across all subjects")
                    .font(.caption)
                    .opacity(0.7)
            }
            Spacer()
            Text("\(total)")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(Pastel.ink)
        .padding(16)
        .tile(Pastel.sky, radius: 26)
    }

    private func ranking(_ ranked: [SubjectStat]) -> some View {
        card(Pastel.lavender) {
            heading("Subject ranking", "From your strongest to your weakest subject")
            VStack(spacing: 8) {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, stat in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(.subheadline, design: .rounded).weight(.heavy))
                            .foregroundStyle(Pastel.ink)
                            .frame(width: 32, height: 32)
                            .background(rankColor(index), in: Circle())
                        Circle()
                            .fill(Pastel.subjectStrong(stat.subject.colorValue))
                            .frame(width: 8, height: 8)
                        Text(stat.subject.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Pastel.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(Int(stat.summary.percentage.rounded()))%")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(Pastel.ink)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Pastel.surface.opacity(index < 3 ? 0.75 : 0.4),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }

    private func rankColor(_ index: Int) -> Color {
        switch index {
        case 0: return Pastel.butter
        case 1: return Pastel.sky
        case 2: return Pastel.peach
        default: return Pastel.surface.opacity(0.6)
        }
    }

    private func subjectChart(_ stats: [SubjectStat]) -> some View {
        card(Pastel.surface) {
            heading("By subject", "Bars show attendance. The dot marks each subject's goal.")
            Chart {
                ForEach(stats) { stat in
                    BarMark(
                        x: .value("Attendance", stat.summary.percentage),
                        y: .value("Subject", stat.subject.name),
                        height: .fixed(18)
                    )
                    .foregroundStyle(Pastel.subjectStrong(stat.subject.colorValue))
                    .cornerRadius(9)

                    PointMark(
                        x: .value("Goal", stat.summary.target),
                        y: .value("Subject", stat.subject.name)
                    )
                    .symbol {
                        Circle()
                            .fill(Color.white)
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.55), lineWidth: 2))
                            .frame(width: 11, height: 11)
                    }
                }
            }
            .chartXScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine().foregroundStyle(Pastel.ink.opacity(0.08))
                    AxisValueLabel {
                        if let v = value.as(Int.self) { Text("\(v)%") }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(Pastel.ink)
                }
            }
            .frame(height: max(160, CGFloat(stats.count) * 40))
        }
    }

    private func trendChart(_ trend: [TrendPoint], target: Double) -> some View {
        card(Pastel.mint) {
            heading("Trend", "Your overall attendance at the end of each week")
            Chart {
                ForEach(trend) { point in
                    AreaMark(
                        x: .value("Week", point.week),
                        y: .value("Attendance", point.percentage)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Pastel.ink.opacity(0.22), Pastel.ink.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Week", point.week),
                        y: .value("Attendance", point.percentage)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .foregroundStyle(Pastel.ink)
                }
                RuleMark(y: .value("Goal", target))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                    .foregroundStyle(Pastel.ink.opacity(0.5))
                    .annotation(position: .top, alignment: .leading) {
                        Text("goal \(Int(target.rounded()))%")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Pastel.ink.opacity(0.7))
                    }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine().foregroundStyle(Pastel.ink.opacity(0.08))
                    AxisValueLabel {
                        if let v = value.as(Int.self) { Text("\(v)%") }
                    }
                }
            }
            .frame(height: 180)
        }
    }

    @ViewBuilder
    private func attention(title: String, systemImage: String, color: Color, items: [SubjectStat]) -> some View {
        if !items.isEmpty {
            card(color) {
                Label(title, systemImage: systemImage)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Pastel.ink)
                ForEach(items) { stat in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(stat.subject.name).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(Int(stat.summary.percentage.rounded()))% of \(Int(stat.summary.target.rounded()))%")
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                        }
                        Text(stat.summary.message).font(.caption).opacity(0.75)
                    }
                    .foregroundStyle(Pastel.ink)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Pastel.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }

    // MARK: Trend data

    private func weeklyTrend(_ sessions: [AttendanceSession]) -> [TrendPoint] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        var byWeek: [Date: WeekCount] = [:]

        for session in sessions {
            guard let subject = session.subject, !subject.isArchived,
                  let day = DateUtils.date(fromISO: session.sessionDate),
                  let week = calendar.dateInterval(of: .weekOfYear, for: day)?.start else { continue }
            var count = byWeek[week] ?? WeekCount()
            for unit in session.units {
                switch unit.status {
                case .present:
                    count.present += 1
                    count.conducted += 1
                case .absent, .bunked:
                    count.conducted += 1
                default:
                    break
                }
            }
            byWeek[week] = count
        }

        var points: [TrendPoint] = []
        var cumulativePresent = 0
        var cumulativeConducted = 0
        for week in byWeek.keys.sorted() {
            let count = byWeek[week] ?? WeekCount()
            cumulativePresent += count.present
            cumulativeConducted += count.conducted
            if cumulativeConducted > 0 {
                points.append(TrendPoint(
                    week: week,
                    percentage: Double(cumulativePresent) / Double(cumulativeConducted) * 100
                ))
            }
        }
        return points
    }
}
