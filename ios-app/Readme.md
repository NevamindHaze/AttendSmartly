# AttendSmartly iOS

Native SwiftUI + SwiftData (iOS 17+) port of the Android app.

## Status
- Home: today's classes from the timetable, mark Present / Absent / Cancelled per unit
- Subjects: add, edit, archive, delete; per-subject % and safe-bunk message
- Settings (gear on Home): import/export the same JSON backup format as Android
- Coming next: Timetable editor, History, Analytics

Data models mirror the Android entities (dates are `yyyy-MM-dd`, times `HH:mm`, weekday 1 = Monday).
The store is named `AttendSmartlyV2`; the first starter build used an older, incompatible schema.
