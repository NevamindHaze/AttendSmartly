import Foundation
import CoreGraphics
import Vision

/// A piece of text found in a photo. `box` is normalised (0...1) with the origin at the top left.
struct ScannedText: Hashable {
    let text: String
    let box: CGRect

    var center: CGPoint { CGPoint(x: box.midX, y: box.midY) }

    static func == (lhs: ScannedText, rhs: ScannedText) -> Bool {
        lhs.text == rhs.text && lhs.box == rhs.box
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(box.origin.x)
        hasher.combine(box.origin.y)
        hasher.combine(box.size.width)
        hasher.combine(box.size.height)
    }
}

/// One class suggested by the scanner, for the person to review.
struct ScannedClass: Hashable {
    var day: Int          // 1 = Monday ... 7 = Sunday
    var start: String     // HH:mm, 24-hour
    var end: String       // HH:mm, 24-hour
    var name: String
}

/// Turns text found in a timetable photo into suggested classes.
///
/// Works with the common grid layouts: days down the side and time slots across the top,
/// or days across the top and time slots down the side. A list such as
/// "Monday 9:00-10:00 Anatomy" on one line is understood too.
enum TimetableScanner {

    // MARK: Text recognition (on device)

    static func recognizeText(in image: CGImage) async throws -> [ScannedText] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            return (request.results ?? []).compactMap { observation -> ScannedText? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                let b = observation.boundingBox  // Vision uses a bottom-left origin
                return ScannedText(text: text, box: CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height))
            }
        }.value
    }

    // MARK: Parsing

    static func parse(_ items: [ScannedText]) -> [ScannedClass] {
        let days = items.compactMap { item in dayIndex(item.text).map { (item, $0) } }
        let times = items.compactMap { item -> (ScannedText, String, String)? in
            guard dayIndex(item.text) == nil, let range = timeRange(item.text) else { return nil }
            // A cell that is mostly a time range is a slot header, not a class.
            let leftover = item.text.replacingOccurrences(
                of: timePattern, with: "", options: [.regularExpression, .caseInsensitive]
            )
            guard leftover.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).count <= 2 else {
                return nil
            }
            return (item, range.0, range.1)
        }

        var results: [ScannedClass]
        if days.count >= 2 && !times.isEmpty {
            results = parseGrid(items: items, days: days, times: times)
        } else {
            results = []
        }
        if results.isEmpty {
            results = parseLines(items)
        }
        return merge(results)
    }

    private static func parseGrid(
        items: [ScannedText],
        days: [(ScannedText, Int)],
        times: [(ScannedText, String, String)]
    ) -> [ScannedClass] {
        let dayXs = days.map { $0.0.center.x }
        let dayYs = days.map { $0.0.center.y }
        // Days stacked vertically means days are rows and time slots are columns.
        let daysAreRows = spread(dayYs) >= spread(dayXs)

        let dayPositions = days.map { (daysAreRows ? $0.0.center.y : $0.0.center.x, $0.1) }
        let dayGap = medianGap(dayPositions.map { $0.0 }) ?? 0.1

        let used = Set(days.map { $0.0 }).union(times.map { $0.0 })
        var found: [ScannedClass] = []

        for item in items where !used.contains(item) {
            let name = cleanName(item.text)
            guard name.count >= 2, !isFiller(name) else { continue }

            // Which day row/column is this cell in?
            let along = daysAreRows ? item.center.y : item.center.x
            guard let nearestDay = dayPositions.min(by: { abs($0.0 - along) < abs($1.0 - along) }),
                  abs(nearestDay.0 - along) <= dayGap * 0.6 else { continue }

            // Which time slots does it cover? Wide cells (labs) can span several.
            let lo = daysAreRows ? item.box.minX : item.box.minY
            let hi = daysAreRows ? item.box.maxX : item.box.maxY
            let slotPositions = times.map { (daysAreRows ? $0.0.center.x : $0.0.center.y, $0.1, $0.2) }
            let slotGap = medianGap(slotPositions.map { $0.0 }) ?? 0.1
            var covered = slotPositions.filter { $0.0 >= lo - slotGap * 0.25 && $0.0 <= hi + slotGap * 0.25 }
            if covered.isEmpty {
                let mid = (lo + hi) / 2
                if let nearest = slotPositions.min(by: { abs($0.0 - mid) < abs($1.0 - mid) }),
                   abs(nearest.0 - mid) <= slotGap * 0.75 {
                    covered = [nearest]
                }
            }
            guard !covered.isEmpty else { continue }
            let start = covered.map { $0.1 }.min() ?? covered[0].1
            let end = covered.map { $0.2 }.max() ?? covered[0].2
            found.append(ScannedClass(day: nearestDay.1, start: start, end: end, name: name))
        }

        // Several lines in one cell (name, room, teacher): keep the top one as the name.
        var byCell: [String: ScannedClass] = [:]
        var order: [String] = []
        for item in found {
            let key = "\(item.day)|\(item.start)|\(item.end)"
            if byCell[key] == nil {
                byCell[key] = item
                order.append(key)
            }
        }
        return order.compactMap { byCell[$0] }
    }

    /// "Monday 9:00 - 10:00 Anatomy" or "Mon 2-4 pm Surgery lab" on a single line.
    private static func parseLines(_ items: [ScannedText]) -> [ScannedClass] {
        var currentDay: Int?
        var results: [ScannedClass] = []
        let ordered = items.sorted { ($0.center.y, $0.center.x) < ($1.center.y, $1.center.x) }
        for item in ordered {
            let words = item.text.split(separator: " ").map(String.init)
            if let first = words.first, let day = dayIndex(first) {
                currentDay = day
            }
            guard let day = currentDay, let range = timeRange(item.text) else { continue }
            var rest = item.text.replacingOccurrences(of: timePattern, with: " ", options: [.regularExpression, .caseInsensitive])
            if let first = words.first, dayIndex(first) != nil, let r = rest.range(of: first) {
                rest.removeSubrange(r)
            }
            let name = cleanName(rest)
            guard name.count >= 2, !isFiller(name) else { continue }
            results.append(ScannedClass(day: day, start: range.0, end: range.1, name: name))
        }
        return results
    }

    /// Joins back-to-back slots of the same class (a two-hour lab printed as two cells).
    private static func merge(_ classes: [ScannedClass]) -> [ScannedClass] {
        let sorted = classes.sorted { ($0.day, $0.start) < ($1.day, $1.start) }
        var merged: [ScannedClass] = []
        for item in sorted {
            if var last = merged.last, last.day == item.day,
               last.name.lowercased() == item.name.lowercased(), last.end == item.start {
                last.end = item.end
                merged[merged.count - 1] = last
            } else if !merged.contains(item) {
                merged.append(item)
            }
        }
        return merged
    }

    // MARK: Pieces

    static func dayIndex(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
        guard t.count >= 2, t.count <= 10 else { return nil }
        let days: [(Int, [String])] = [
            (1, ["mon", "monday"]), (2, ["tue", "tues", "tuesday"]), (3, ["wed", "weds", "wednesday"]),
            (4, ["thu", "thur", "thurs", "thursday"]), (5, ["fri", "friday"]),
            (6, ["sat", "saturday"]), (7, ["sun", "sunday"]),
        ]
        for (index, names) in days where names.contains(t) { return index }
        return nil
    }

    static let timePattern =
        #"(\d{1,2})(?:[:.](\d{2}))?\s*([ap]\.?m\.?)?\s*(?:-|–|—|to)\s*(\d{1,2})(?:[:.](\d{2}))?\s*([ap]\.?m\.?)?"#

    /// Reads a time range such as "9:00-10:00", "09.00 – 10.00", "2-4 pm" or "11 am to 1 pm".
    /// Without am/pm, times from 1 to 7 are taken as afternoon, which suits college timetables.
    static func timeRange(_ text: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: timePattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ i: Int) -> String? {
            guard let r = Range(m.range(at: i), in: text) else { return nil }
            return String(text[r])
        }
        guard let h1 = Int(group(1) ?? ""), let h2 = Int(group(4) ?? "") else { return nil }
        let m1 = Int(group(2) ?? "0") ?? 0
        let m2 = Int(group(5) ?? "0") ?? 0
        guard (0...23).contains(h1), (0...23).contains(h2), (0...59).contains(m1), (0...59).contains(m2) else { return nil }
        let p1 = group(3)?.lowercased().first
        let p2 = group(6)?.lowercased().first

        func to24(_ h: Int, _ period: Character?) -> Int {
            if let period {
                if period == "p" { return h == 12 ? 12 : h + 12 }
                return h == 12 ? 0 : h
            }
            if h >= 13 { return h }
            return (1...7).contains(h) ? h + 12 : h
        }
        // "2-4 pm": the end's am/pm applies to the start as well.
        var start = to24(h1, p1 ?? p2)
        var end = to24(h2, p2 ?? p1)
        if p1 == nil && p2 != nil && start > end { start -= 12 }   // "11-1 pm" → 11:00–13:00
        if end * 60 + m2 <= start * 60 + m1, end + 12 <= 23 { end += 12 }
        guard end * 60 + m2 > start * 60 + m1 else { return nil }
        return (String(format: "%02d:%02d", start, m1), String(format: "%02d:%02d", end, m2))
    }

    private static func cleanName(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func isFiller(_ name: String) -> Bool {
        let fillers = ["break", "lunch", "lunch break", "recess", "free", "tea break", "day", "time", "timing", "timings"]
        let lower = name.lowercased()
        return fillers.contains(lower) || lower.allSatisfy { $0.isNumber || $0 == ":" || $0 == "." || $0 == " " }
    }

    private static func spread(_ values: [CGFloat]) -> CGFloat {
        (values.max() ?? 0) - (values.min() ?? 0)
    }

    private static func medianGap(_ values: [CGFloat]) -> CGFloat? {
        let sorted = values.sorted()
        guard sorted.count >= 2 else { return nil }
        let gaps = zip(sorted.dropFirst(), sorted).map { $0 - $1 }.filter { $0 > 0.005 }.sorted()
        guard !gaps.isEmpty else { return nil }
        return gaps[gaps.count / 2]
    }
}
