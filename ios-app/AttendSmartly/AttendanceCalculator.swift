import Foundation

struct AttendanceSummary {
    let present: Int
    let absent: Int
    let cancelled: Int
    let conducted: Int
    let percentage: Double
    let target: Double
    let safeBunks: Int
    let requiredUnits: Int
    let message: String
}

/// Port of the Android AttendanceCalculator.
enum AttendanceCalculator {
    static func summary(statuses: [AttendanceStatus], target: Double = 75) -> AttendanceSummary {
        let present = statuses.filter { $0 == .present }.count
        let absent = statuses.filter { $0 == .absent || $0 == .bunked }.count
        let cancelled = statuses.filter { $0 == .cancelled }.count
        let safeTarget = min(max(target, 1), 100)

        let p = Double(present)
        let a = Double(absent)
        let t = p + a
        let pct = t > 0 ? (p / t) * 100 : 0

        var safe = 0
        if t > 0 && p > 0 {
            let calc = ((100 * p - safeTarget * t) / safeTarget + 1e-9).rounded(.down)
            if calc > 0 && calc.isFinite { safe = Int(calc) }
        }

        var required = 0
        if t == 0 || pct >= safeTarget - 1e-9 {
            required = 0
        } else if safeTarget >= 100 {
            required = absent > 0 ? Int.max : 0
        } else {
            let calc = ((safeTarget * t - 100 * p) / (100 - safeTarget) - 1e-9).rounded(.up)
            if calc > 0 && calc.isFinite { required = Int(calc) }
        }

        let rounded = Int(safeTarget.rounded())
        let message: String
        if present + absent == 0 {
            message = "No attendance recorded yet."
        } else if required == Int.max {
            message = "Target is 100%. Cannot reach it after an absence."
        } else if pct < safeTarget - 1e-9 {
            message = "Attend the next \(required) \(required == 1 ? "unit" : "units") to reach \(rounded)%."
        } else if safe > 0 {
            message = "You can safely miss \(safe) \(safe == 1 ? "unit" : "units") and stay above \(rounded)%."
        } else {
            message = "You're right on the margin of your \(rounded)% target. Don't miss the next class."
        }

        return AttendanceSummary(
            present: present, absent: absent, cancelled: cancelled, conducted: present + absent,
            percentage: pct, target: safeTarget, safeBunks: safe, requiredUnits: required, message: message
        )
    }
}
