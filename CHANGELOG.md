# Changelog

Builds are published to the SideStore source as version `1.0.<build number>`.

## October 2026: first iOS release

- Native SwiftUI app with SwiftData storage (iOS 17+).
- Home: greeting with profile photo, overall attendance, goal progress, quick stats and today's classes with per-unit marking.
- Subjects: add, edit, archive and delete, with a percentage, goal bar and safe-bunk verdict for each.
- Timetable: weekly day picker, class editor with rooms, teachers, units and date ranges.
- Any-date attendance, extra classes, cancelling and rescheduling.
- History with editing, and adding past classes.
- Analytics: overall ring, best and weakest subject, subject ranking, per-subject bars and weekly trend.
- Holidays, semester tracking and weekly class reminders.
- JSON backup import and export, compatible with the Android app; merging no longer duplicates subjects.
- Pastel design in light mode and jewel tones in dark mode; custom app icon.
- Unit tests and GitHub Actions CI that publishes each build to a SideStore source.

The original Android app's history is on the [`android-archive`](https://github.com/NevamindHaze/AttendSmartly/tree/android-archive) branch.
