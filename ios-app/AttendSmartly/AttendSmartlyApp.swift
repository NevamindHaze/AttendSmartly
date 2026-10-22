import SwiftUI
import SwiftData

@main
struct AttendSmartlyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            Subject.self,
            TimetableEntry.self,
            AttendanceSession.self,
            AttendanceUnit.self,
            Holiday.self
        ])
    }
}
