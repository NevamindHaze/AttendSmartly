# AttendSmartly iOS Roadmap

A living checklist for the native iOS app. This roadmap tracks iOS work separately from the Android roadmap in the repository root.

**Status snapshot:** 2026-10-26  
**Supported baseline:** iOS 17+  
**Priority:** P0 = correctness/release foundation; P1 = core product parity; P2 = polish and platform-specific follow-ups.

## Current baseline

- [x] Home dashboard with today's classes, overall attendance summary, and per-unit marking.
- [x] Subject add/edit/archive/delete and subject-level attendance summaries.
- [x] Weekly timetable add/edit/delete.
- [x] Attendance history, edits, and manual past-class entry.
- [x] Android-compatible JSON backup import/export with merge or replace.
- [x] App icon asset catalog implemented and device/simulator builds passed; [PR #1](https://github.com/NevamindHaze/AttendSmartly/pull/1) is awaiting merge.

## P0 — Correctness and release foundation

- [x] Align active timetable and date-window filtering across Home and Timetable. The weekly view resolves the selected weekday to its date in the current week; both screens use inclusive start/end bounds. Current recurrence is one weekly weekday per entry, matching Android's day/date query; `repeatType` remains backup compatibility data. Implemented in [PR #3](https://github.com/NevamindHaze/AttendSmartly/pull/3); simulator and device builds passed.
- [ ] Add an iOS test target for attendance calculations, date/recurrence boundaries, and Android backup import/export. Include boundary cases and a representative backup fixture.
- [ ] Replace the SwiftData startup `fatalError` with a recoverable error path and a safe, documented recovery option.
- [ ] Complete a real-device smoke pass: create a subject and schedule, mark multiple units, relaunch, edit history, and import/export a backup without data loss.
- [ ] Choose a signing and distribution route. The current CI device artifact is unsigned; document the steps for installing a development build or publishing through TestFlight.

## P1 — Core feature parity

- [ ] Build the Analytics screen in place of the current placeholder. Include overall and per-subject attendance, target progress, safe bunks/recovery units, and useful date or semester filtering.
- [ ] Add holiday management: create, edit, and delete holidays, and verify that holidays suppress scheduled classes on the matching date.
- [ ] Add one-off extra classes that do not change the recurring timetable.
- [ ] Add class rescheduling with a reason, a visible rescheduled marker, and a reliable undo/revert action.
- [ ] Add native local class reminders, including permission handling, per-class reminder timing, and cancellation/rescheduling when timetable entries change.

## P2 — Polish and platform decisions

- [ ] Review VoiceOver labels, Dynamic Type, contrast, focus order, and touch target sizes on every main screen.
- [ ] Decide which Android-specific capabilities merit native iOS counterparts: timetable OCR, location-based auto-attendance, widgets, and calendar sync. For each, record privacy, permission, battery, and maintenance tradeoffs before implementation.
- [ ] Review semester boundaries and historical reporting once the core date-filtering behavior is stable.

## Completion checklist for each feature

- [ ] Acceptance behavior is written down and the checklist item is updated.
- [ ] The iOS simulator and generic device builds pass.
- [ ] Relevant automated coverage and a focused manual check pass.
- [ ] Android backup compatibility is preserved when data formats are involved.
- [ ] The shipped behavior and any required permissions are documented in the iOS README.

Dates and release numbers are intentionally left open until the user prioritizes the work.
