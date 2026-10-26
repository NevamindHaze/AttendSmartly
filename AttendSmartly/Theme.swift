import SwiftUI

// MARK: - Attendance health

/// Attendance is a health signal, so colour carries three levels:
/// comfortably above target, close to target (within 5 points), and below target.
func attendanceTint(_ summary: AttendanceSummary) -> Color {
    if summary.conducted == 0 { return .secondary }
    let margin = summary.percentage - summary.target
    if margin < 0 { return DashboardPalette.coral }
    if margin <= 5 { return DashboardPalette.amber }
    return DashboardPalette.green
}

func attendanceLabel(_ summary: AttendanceSummary) -> String {
    if summary.conducted == 0 { return "No classes yet" }
    let margin = summary.percentage - summary.target
    if margin < 0 { return "Below target" }
    if margin <= 5 { return "Close to target" }
    return "On track"
}

// MARK: - Surfaces

extension View {
    /// One card surface for the whole app. Bigger radius = more important surface.
    func cardStyle(_ radius: CGFloat = 16) -> some View {
        self
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }
}

// MARK: - Progress ring

struct ProgressRing<Center: View>: View {
    let value: Double
    var target: Double? = nil
    let tint: Color
    var lineWidth: CGFloat = 14
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.16), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: CGFloat(min(max(value, 0), 100) / 100))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.7, dampingFraction: 0.85), value: value)

            if let target {
                GeometryReader { geo in
                    let radius = min(geo.size.width, geo.size.height) / 2 - lineWidth / 2
                    let knob = max(8, lineWidth * 0.8)
                    ZStack {
                        // Goal marker: a small light knob sitting on the ring at the target.
                        Circle()
                            .fill(Color.white)
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.55), lineWidth: 2))
                            .frame(width: knob, height: knob)
                            .shadow(color: .black.opacity(0.25), radius: 1.5)
                            .offset(y: -radius)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .rotationEffect(.degrees(min(max(target, 0), 100) / 100 * 360))
                }
            }

            center()
        }
    }
}

// MARK: - Small pieces

struct StatusPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(DashboardPalette.green)
                .frame(width: 64, height: 64)
                .background(DashboardPalette.green.opacity(0.12), in: Circle())
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}
