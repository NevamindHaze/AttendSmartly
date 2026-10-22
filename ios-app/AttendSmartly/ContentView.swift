import SwiftUI

struct ContentView: View {
    @State private var selectedTab: DashboardTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeDashboardView()
            }
            .tabItem {
                Label(DashboardTab.home.title, systemImage: DashboardTab.home.symbol)
            }
            .tag(DashboardTab.home)

            placeholderTab(.subjects, message: "Your subjects will appear here.")
            placeholderTab(.timetable, message: "Your weekly class schedule will appear here.")
            placeholderTab(.history, message: "Your attendance records will appear here.")
            placeholderTab(.analytics, message: "Your attendance insights will appear here.")
        }
        .tint(DashboardPalette.green)
    }

    private func placeholderTab(_ tab: DashboardTab, message: String) -> some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(DashboardPalette.green)
                Text(tab.title)
                    .font(.title3.bold())
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .navigationTitle(tab.title)
            .navigationBarTitleDisplayMode(.large)
        }
        .tabItem {
            Label(tab.title, systemImage: tab.symbol)
        }
        .tag(tab)
    }
}

private struct HomeDashboardView: View {
    private let attendedClasses = 18
    private let totalClasses = 20
    private let scheduledClasses = [
        ScheduledClass(
            startTime: "9:00 AM",
            endTime: "10:00 AM",
            subject: "Data Structures",
            code: "CSE 201",
            room: "Engineering Hall 204",
            color: DashboardPalette.green
        ),
        ScheduledClass(
            startTime: "11:00 AM",
            endTime: "12:30 PM",
            subject: "Linear Algebra",
            code: "MATH 101",
            room: "North Hall 118",
            color: DashboardPalette.blue
        ),
        ScheduledClass(
            startTime: "2:00 PM",
            endTime: "3:30 PM",
            subject: "Design Studio",
            code: "DES 220",
            room: "Arts Building 12",
            color: DashboardPalette.coral
        )
    ]

    private var attendanceRate: Double {
        Double(attendedClasses) / Double(totalClasses)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AttendSmartly")
                        .font(.largeTitle.bold())
                        .foregroundStyle(DashboardPalette.ink)
                    Label(
                        Date.now.formatted(date: .complete, time: .omitted),
                        systemImage: "calendar"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                attendanceSummary

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Today's classes")
                            .font(.title2.bold())
                            .foregroundStyle(DashboardPalette.ink)
                        Spacer()
                        Text("\(scheduledClasses.count) scheduled")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(scheduledClasses.enumerated()), id: \.element.id) { index, classItem in
                            ScheduledClassRow(classItem: classItem)

                            if index < scheduledClasses.count - 1 {
                                Divider()
                                    .padding(.leading, 94)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var attendanceSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overall attendance")
                        .font(.headline)
                        .foregroundStyle(DashboardPalette.ink)
                    Text("Across all subjects")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text("On track")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardPalette.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DashboardPalette.green.opacity(0.1), in: Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(attendanceRate * 100))%")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(DashboardPalette.green)
                Text("attendance")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: attendanceRate)
                .tint(DashboardPalette.green)

            HStack(spacing: 0) {
                attendanceMetric(value: attendedClasses, label: "Attended")
                Spacer()
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 1, height: 30)
                Spacer()
                attendanceMetric(value: totalClasses, label: "Total classes")
            }
            .padding(.top, 2)
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func attendanceMetric(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .font(.title3.bold())
                .foregroundStyle(DashboardPalette.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ScheduledClass: Identifiable {
    let id = UUID()
    let startTime: String
    let endTime: String
    let subject: String
    let code: String
    let room: String
    let color: Color
}

private struct ScheduledClassRow: View {
    let classItem: ScheduledClass

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(classItem.startTime)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DashboardPalette.ink)
                Text(classItem.endTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 66, alignment: .leading)

            RoundedRectangle(cornerRadius: 2)
                .fill(classItem.color)
                .frame(width: 4, height: 44)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(classItem.subject)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DashboardPalette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(classItem.code)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Label(classItem.room, systemImage: "mappin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
    }
}

private enum DashboardTab: String, CaseIterable {
    case home
    case subjects
    case timetable
    case history
    case analytics

    var title: String {
        switch self {
        case .home: "Home"
        case .subjects: "Subjects"
        case .timetable: "Timetable"
        case .history: "History"
        case .analytics: "Analytics"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .subjects: "book.closed"
        case .timetable: "calendar"
        case .history: "clock.arrow.circlepath"
        case .analytics: "chart.bar.xaxis"
        }
    }
}

private enum DashboardPalette {
    static let green = Color(red: 0.12, green: 0.42, blue: 0.34)
    static let blue = Color(red: 0.26, green: 0.48, blue: 0.72)
    static let coral = Color(red: 0.82, green: 0.38, blue: 0.29)
    static let ink = Color.primary
}

#Preview {
    ContentView()
}