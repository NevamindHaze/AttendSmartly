import Foundation

/// UserDefaults / @AppStorage keys.
enum PrefKey {
    static let semesterEnabled = "semesterEnabled"
    static let semesterStart = "semesterStart"
    static let semesterEnd = "semesterEnd"
    static let remindersEnabled = "remindersEnabled"
}

/// Optional date window that limits which sessions count towards attendance
/// (mirrors the Android "track by semester" option). Dates are yyyy-MM-dd strings.
struct SemesterRange {
    var enabled: Bool
    var start: String
    var end: String

    func includes(_ isoDate: String) -> Bool {
        guard enabled else { return true }
        if !start.isEmpty && isoDate < start { return false }
        if !end.isEmpty && isoDate > end { return false }
        return true
    }
}
