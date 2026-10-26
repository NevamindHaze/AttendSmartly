import SwiftUI
import SwiftData

@main
struct AttendSmartlyApp: App {
    private let container: ModelContainer

    init() {
        let schema = Schema([
            Subject.self,
            TimetableEntry.self,
            AttendanceSession.self,
            AttendanceUnit.self,
            Holiday.self,
            Assignment.self
        ])
        // New store name: the first starter build used an incompatible schema.
        let config = ModelConfiguration("AttendSmartlyV2", schema: schema)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create the data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
