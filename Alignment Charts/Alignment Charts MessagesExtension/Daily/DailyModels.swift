import Foundation

/// A shared UTC calendar, independent of device time zone and daylight saving.
enum DailyCalendar {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    static func day(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    static func date(for day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...9999).contains(parts[0]),
              (1...12).contains(parts[1]), (1...31).contains(parts[2]),
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              self.day(for: date) == day else { return nil }
        return date
    }

    static func nextReset(after date: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
    }

    static func includes(_ date: Date, in day: String) -> Bool {
        guard let start = self.date(for: day) else { return false }
        return date >= start && date < nextReset(after: start)
    }
}

struct DailyIdentity: Codable, Equatable, Sendable {
    let day: String
    let templateID: String
}

struct DailyTemplate: Codable, Identifiable, Equatable, Sendable {
    let day: String
    let title: String
    let prompt: String
    let rowAxisTitle: String
    let columnAxisTitle: String
    let rowLabels: [String]
    let columnLabels: [String]

    var id: String { "daily-\(day)" }
    var isValid: Bool {
        DailyCalendar.date(for: day) != nil && !title.isEmpty
            && ChartState.sizeRange.contains(rowLabels.count)
            && ChartState.sizeRange.contains(columnLabels.count)
            && (rowLabels + columnLabels).allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func makeChart() -> ChartState {
        var chart = ChartState(rows: rowLabels.count, columns: columnLabels.count)
        chart.title = title
        chart.rowAxisTitle = rowAxisTitle
        chart.columnAxisTitle = columnAxisTitle
        chart.rowLabels = rowLabels
        chart.columnLabels = columnLabels
        chart.daily = DailyIdentity(day: day, templateID: id)
        return chart
    }

    /// Keep a daily available if the editorial schedule runs out, using a stable rotation.
    static func fallback(for day: String, from catalog: [DailyTemplate]) -> DailyTemplate? {
        let sorted = catalog.filter(\.isValid).sorted { $0.day < $1.day }
        guard let first = sorted.first, let start = DailyCalendar.date(for: first.day),
              let date = DailyCalendar.date(for: day), date >= start else { return nil }
        let offset = DailyCalendar.calendar.dateComponents([.day], from: start, to: date).day!
        let source = sorted[offset % sorted.count]
        return DailyTemplate(day: day, title: source.title, prompt: source.prompt,
                             rowAxisTitle: source.rowAxisTitle, columnAxisTitle: source.columnAxisTitle,
                             rowLabels: source.rowLabels, columnLabels: source.columnLabels)
    }

    static func bundled(in bundle: Bundle = .main) -> [DailyTemplate] {
        guard let url = bundle.url(forResource: "DailyTemplates", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let templates = try? JSONDecoder().decode([DailyTemplate].self, from: data) else { return [] }
        return templates.filter(\.isValid)
    }
}

struct StreakSummary: Equatable {
    let current: Int
    let best: Int
    let claimedToday: Bool

    init(days: Set<String>, now: Date) {
        let today = DailyCalendar.day(for: now)
        claimedToday = days.contains(today)
        var cursor = DailyCalendar.calendar.startOfDay(for: now)
        if !claimedToday { cursor = DailyCalendar.calendar.date(byAdding: .day, value: -1, to: cursor)! }
        var length = 0
        while days.contains(DailyCalendar.day(for: cursor)) {
            length += 1
            cursor = DailyCalendar.calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        current = length
        var longest = 0
        var run = 0
        var previous: Date?
        for day in days.sorted() {
            guard let date = DailyCalendar.date(for: day), date <= now else { continue }
            run = previous.map { DailyCalendar.nextReset(after: $0) == date } == true ? run + 1 : 1
            longest = max(longest, run)
            previous = date
        }
        best = longest
    }
}
