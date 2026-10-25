# AttendSmartly iOS

Native SwiftUI + SwiftData (iOS 17+) port of the Android app.

## Status
- Home: today's classes from the timetable, mark Present / Absent / Cancelled per unit
- Subjects: add, edit, archive, delete; per-subject % and safe-bunk message
- Settings (gear on Home): import/export the same JSON backup format as Android
- Timetable: weekly view, add/edit/delete classes
- History: past sessions grouped by date, fix marks, add past classes
- Analytics: overall counts, best/lowest subject, per-subject chart with targets, weekly trend, below/near-target lists
- Holidays (Settings → Holidays), extra classes (+ on Home), cancel / reschedule a class (… on a class card)
- Class reminders and semester tracking (Settings)
- Not built yet: location auto-attendance, AI timetable scan, update checker

Data models mirror the Android entities (dates are `yyyy-MM-dd`, times `HH:mm`, weekday 1 = Monday).
The store is named `AttendSmartlyV2`; the first starter build used an older, incompatible schema.
