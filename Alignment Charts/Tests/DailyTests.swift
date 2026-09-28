import Foundation

@main
struct DailyTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fatalError("FAILED: \(message)") }
    }
    static func main() throws {
        let start = DailyCalendar.date(for: "2026-09-06")!
        let reset = DailyCalendar.nextReset(after: start)
        expect(DailyCalendar.includes(start, in: "2026-09-06"), "day starts inclusively")
        expect(DailyCalendar.includes(reset.addingTimeInterval(-0.001), in: "2026-09-06"), "claim just before reset allowed")
        expect(!DailyCalendar.includes(reset, in: "2026-09-06"), "claim exactly at reset rejected")
        expect(!DailyCalendar.includes(start.addingTimeInterval(-1), in: "2026-09-06"), "future template rejected")
        expect(DailyCalendar.day(for: reset) == "2026-09-07", "rotation shares claim boundary")
        expect(DailyCalendar.date(for: "2026-02-30") == nil, "invalid day rejected")
        expect(DailyCalendar.date(for: "2026-9-6") == nil, "noncanonical day rejected")
        for day in ["2026-03-08", "2026-11-01", "2026-12-31"] {
            let date = DailyCalendar.date(for: day)!
            expect(DailyCalendar.nextReset(after: date).timeIntervalSince(date) == 86400, "UTC reset always 24h, including DST/year rollover")
        }
        var days: Set<String> = ["2026-09-06", "2026-09-07"]
        var summary = StreakSummary(days: days, now: DailyCalendar.date(for: "2026-09-08")!)
        expect(summary.current == 2 && !summary.claimedToday, "yesterday's streak remains alive during today's claim window")
        days.insert("2026-09-08")
        days.insert("2026-09-08")
        summary = StreakSummary(days: days, now: DailyCalendar.date(for: "2026-09-08")!)
        expect(summary.current == 3 && summary.claimedToday && summary.best == 3, "multiple chats/taps count once")
        summary = StreakSummary(days: days, now: DailyCalendar.date(for: "2026-09-10")!)
        expect(summary.current == 0 && summary.best == 3, "missed day resets current but retains best")
        days.insert("2026-09-10")
        summary = StreakSummary(days: days, now: DailyCalendar.date(for: "2026-09-10")!)
        expect(summary.current == 1 && summary.best == 3, "restart after a gap")
        let empty = StreakSummary(days: [], now: start)
        expect(empty.current == 0 && empty.best == 0 && !empty.claimedToday, "new user")
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let templates = try JSONDecoder().decode([DailyTemplate].self, from: data)
        expect(templates.count == 86 && Set(templates.map(\.id)).count == 86, "unique scheduled days through November 30")
        let autumn = templates.filter { $0.day >= "2026-09-22" }
        expect(autumn.count == 70 && Set(autumn.map(\.title)).count == 70, "70 distinct new themes")
        expect(autumn.first?.title == "Cozy Season" && autumn.last?.day == "2026-11-30", "new schedule includes today and more than two months")
        for (index, template) in templates.enumerated() {
            expect(template.isValid, "template valid")
            expect(template.day == DailyCalendar.day(for: start.addingTimeInterval(Double(index) * 86400)), "schedule contiguous from September 6")
            let chart = template.makeChart()
            expect(chart.isValid && chart.cells.count == 9 && chart.filledCellCount == 0, "template creates empty valid grid")
            expect(chart.id != template.makeChart().id, "each use creates independent collaboration")
            expect(chart.daily == DailyIdentity(day: template.day, templateID: template.id), "date identity travels with chart")
            expect(tryRoundtrip(chart), "daily identity survives serialization")
        }
        let fallback = DailyTemplate.fallback(for: "2026-12-01", from: templates)!
        expect(fallback.title == templates[0].title && fallback.day == "2026-12-01", "schedule exhaustion rotates with today's identity")
        expect(fallback.makeChart().daily?.day == "2026-12-01", "fallback credit belongs to new day")
        expect(DailyTemplate.fallback(for: "2026-09-05", from: templates) == nil, "no daily before launch")
        expect(DailyTemplate.fallback(for: "2026-12-01", from: []) == nil, "missing catalog handled")
        let legacy = ChartState()
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        object.removeValue(forKey: "daily")
        let decoded = try JSONDecoder().decode(ChartState.self, from: JSONSerialization.data(withJSONObject: object))
        expect(decoded.daily == nil && decoded.isValid, "old messages/drafts still decode")
        let base = templates[0].makeChart()
        var local = base
        var remote = base
        local.daily = nil // Simulate an older app that drops unknown JSON fields.
        local.cells[0].caption = "A"
        remote.cells[1].caption = "B"
        let merged = ChartMerge.merge(base: base, local: local, remote: remote)
        expect(merged.conflicts.isEmpty && merged.chart.daily == base.daily, "merge preserves published template identity")
        expect(merged.chart.filledCellCount == 2, "daily collaboration retains everyone's work")
        let resolved = ChartMerge.merge(base: nil, local: local, remote: remote, choices: ["chart": .mine])
        expect(resolved.chart.daily == remote.daily, "legacy whole-chart conflict cannot remove daily identity")
        print("Passed \(checks) daily template and streak checks")
    }
    static func tryRoundtrip(_ chart: ChartState) -> Bool {
        guard let data = try? JSONEncoder().encode(chart), let decoded = try? JSONDecoder().decode(ChartState.self, from: data) else { return false }
        return decoded == chart
    }
}
