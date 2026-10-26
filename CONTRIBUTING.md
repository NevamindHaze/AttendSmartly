# Contributing

AttendSmartly for iOS is a personal project, but bug reports and ideas are welcome.

## Reporting a bug or suggesting a feature

Open an [issue](https://github.com/NevamindHaze/AttendSmartly/issues/new/choose) and pick the matching template. Screenshots help a lot.

## Making a change

1. Fork the repository and create a branch from `main`.
2. Open `AttendSmartly.xcodeproj` in Xcode 16 or later.
3. Keep changes focused, and add or update tests in `AttendSmartlyTests` when you touch the attendance maths or backups.
4. Run the tests with **⌘U**.
5. Open a pull request describing what changed and why. The **Build iOS App** workflow must pass.

## Guidelines

- SwiftUI and SwiftData only; please avoid adding third-party dependencies.
- Use the shared colours and tiles in `Pastel.swift` and `Theme.swift` so screens stay consistent in light and dark mode.
- Keep backups compatible with the Android AttendSmartly format.

By contributing, you agree that your contributions are licensed under the [GPL-3.0](LICENSE).

## Releasing

Every push to `main` that builds successfully is published to the SideStore source. The store listing comes from `.github/sidestore/`:

- `about.md`: the app description
- `whats-new.md`: notes for the next build; update it with each user-facing change
- `news.json`: posts for SideStore's News tab

Screenshots live in `docs/screenshots/` and the source banner in `docs/sidestore/header.png`.
