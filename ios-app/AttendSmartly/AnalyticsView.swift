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
        let best = tracked.max { $0.summary.percentage < $1.summary.percentage }
        let lowest = tracked.min { $0.summary.percentage < $1.summary.percentage }
        let totalSafe = tracked.map { $0.summary.safeBunks }.reduce(0, +)
        let trend = weeklyTrend(sessions)

        NavigationStack {
            ScrollView {
                if tracked.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(DashboardPalette.green)
                        Text("Nothing to analyse yet").font(.title3.bold())
                        Text("Mark some classes or import a backup and your insights will show up here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        overallCard(overall, statuses: allStatuses)
                        highlights(best: best, lowest: lowest, totalSafe: totalSafe)
                        subjectChart(tracked)
                        if trend.count >= 2 { trendChart(trend, target: target) }
                        attention(title: "Below target", systemImage: "exclamationmark.triangle.fill",
                                  tint: DashboardPalette.coral, items: below)
                        attention(title: "Close to target", systemImage: "eye.fill",
                                  tint: .orange, items: near)
                    }
                    .padding()
                }
            }
            .navigationTitle("Analytics")
        }
    }

    // MARK: Sections

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func overallCard(_ overall: AttendanceSummary, statuses: [AttendanceStatus]) -> some View {
        let onTrack = overall.percentage >= overall.target
        let tint = onTrack ? DashboardPalette.green : DashboardPalette.coral
        func count(_ s: AttendanceStatus) -> Int { statuses.filter { $0 == s }.count }

        return card {
            Text("Overall attendance").font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(overall.percentage.rounded()))%")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                Text("of \(Int(overall.target.rounded()))% target").foregroundStyle(.secondary)
            }
            ProgressView(value: min(overall.percentage, 100), total: 100).tint(tint)
            HStack {
                countChip("Present", count(.present), AttendanceStatus.present.tint)
                countChip("Absent", count(.absent), AttendanceStatus.absent.tint)
                countChip("Bunked", count(.bunked), AttendanceStatus.bunked.tint)
                countChip("Cancelled", count(.cancelled), AttendanceStatus.cancelled.tint)
            }
            Text(overall.message).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func countChip(_ title: String, _ value: Int, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title3.bold()).foregroundStyle(tint)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func highlights(best: SubjectStat?, lowest: SubjectStat?, totalSafe: Int) -> some View {
        card {
            Text("Highlights").font(.headline)
            if let best {
                highlightRow("Best subject", best.subject.name, "\(Int(best.summary.percentage.rounded()))%", DashboardPalette.green)
            }
            if let lowest {
                highlightRow("Lowest subject", lowest.subject.name, "\(Int(lowest.summary.percentage.rounded()))%", DashboardPalette.coral)
            }
            highlightRow("Safe bunks across subjects", "Units you can miss in total", "\(totalSafe)", DashboardPalette.blue)
        }
    }

    private func highlightRow(_ title: String, _ detail: String, _ value: String, _ tint: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value).font(.title3.bold()).foregroundStyle(tint)
        }
    }

    private func subjectChart(_ stats: [SubjectStat]) -> some View {
        card {
            Text("By subject").font(.headline)
            Text("Bars show attendance; the diamond marks each subject's target.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Chart {
                ForEach(stats) { stat in
                    BarMark(
                        x: .value("Attendance", stat.summary.percentage),
                        y: .value("Subject", stat.subject.name)
                    )
                    .foregroundStyle(stat.summary.percentage >= stat.summary.target
                                     ? DashboardPalette.green : DashboardPalette.coral)

                    PointMark(
                        x: .value("Target", stat.summary.target),
                        y: .value("Subject", stat.subject.name)
                    )
                    .symbol(.diamond)
                    .symbolSize(60)
                    .foregroundStyle(Color.primary)
                }
            }
            .chartXScale(domain: 0...100)
            .frame(height: max(160, CGFloat(stats.count) * 38))
        }
    }

    private func trendChart(_ trend: [TrendPoint], target: Double) -> some View {
        card {
            Text("Trend").font(.headline)
            Text("Cumulative attendance at the end of each week.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Chart {
                ForEach(trend) { point in
                    LineMark(
                        x: .value("Week", point.week),
                        y: .value("Attendance", point.percentage)
                    )
                    .foregroundStyle(DashboardPalette.green)
                    .interpolationMethod(.monotone)
                    PointMark(
                        x: .value("Week", point.week),
                        y: .value("Attendance", point.percentage)
                    )
                    .foregroundStyle(DashboardPalette.green)
                }
                RuleMark(y: .value("Target", target))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.secondary)
            }
            .chartYScale(domain: 0...100)
            .frame(height: 180)
        }
    }

    @ViewBuilder
    private func attention(title: String, systemImage: String, tint: Color, items: [SubjectStat]) -> some View {
        if !items.isEmpty {
            card {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                ForEach(items) { stat in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(stat.subject.name).font(.subheadline.bold())
                            Spacer()
                            Text("\(Int(stat.summary.percentage.rounded()))% / \(Int(stat.summary.target.rounded()))%")
                                .font(.subheadline)
                                .foregroundStyle(tint)
                        }
                        Text(stat.summary.message).font(.caption).foregroundStyle(.secondary)
                    }
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
