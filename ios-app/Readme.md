# AttendSmartly iOS Starter

A minimal native iOS app built with SwiftUI.

## Open and run

Open `AttendSmartly.xcodeproj` in Xcode, select the `AttendSmartly` scheme, and run it on an iOS simulator or device.

The home screen uses sample attendance data and placeholder sections for subjects and the timetable. No external packages or services are required.

## Local data models

The app uses SwiftData (iOS 17 or later) to store data locally on the device. `Models.swift` defines:

- `Subject`, including its attendance target, archive state, notes, and color identifier.
- `TimetableEntry`, related to a subject, with a weekday (Monday = 1 through Sunday = 7), 24-hour `HH:mm` start/end times, and optional date range.
- `AttendanceSession`, related to a subject and containing attendance units.
- `AttendanceUnit`, related to a session and storing its attendance status.
- `Holiday`, with a date, name, and optional notes.

Each model has a stable UUID identifier. Deleting a subject also deletes its timetable entries and attendance sessions; deleting a session deletes its units. The SwiftData container is registered at app startup. The current dashboard remains sample data and does not yet read or edit these stored models.
