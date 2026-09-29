import UIKit
import Messages

@MainActor
enum MessageComposer {
    /// Builds the interactive bubble. Reusing the session from a received
    /// message makes the send update the existing bubble in place for the
    /// whole thread instead of adding a new one.
    static func message(for chart: ChartState, image: UIImage?, session: MSSession?) -> MSMessage {
        let message = MSMessage(session: session ?? MSSession())

        let layout = MSMessageTemplateLayout()
        layout.image = image
        let caption = chart.title.isEmpty ? "Alignment Chart" : chart.title
        layout.caption = caption
        layout.subcaption = chart.isComplete
            ? "Complete — every cell is filled!"
            : "\(chart.filledCellCount) of \(chart.cells.count) filled — tap to contribute"
        if let daily = chart.daily {
            layout.subcaption = chart.isComplete
                ? "Daily \(daily.day) complete — tap to claim before reset"
                : "Daily \(daily.day) • \(chart.filledCellCount)/\(chart.cells.count) — tap to contribute"
        }
        message.layout = layout

        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "id", value: chart.id.uuidString)]
        if chart.isComplete, let daily = chart.daily {
            components.queryItems?.append(contentsOf: [
                URLQueryItem(name: "completedDay", value: daily.day),
                URLQueryItem(name: "templateID", value: daily.templateID)
            ])
        }
        message.url = components.url
        message.summaryText = chart.isComplete
            ? "\(caption) is complete!"
            : "Contribute to \(caption)"
        return message
    }

    /// Kind-aware entry point: grid charts keep the exact legacy behavior above;
    /// tier charts get their own bubble copy and a `kind=tier` URL marker.
    static func message(for content: ChartContent, image: UIImage?, session: MSSession?) -> MSMessage {
        switch content {
        case .grid(let chart):
            return message(for: chart, image: image, session: session)
        case .tier(let tier):
            return tierMessage(for: tier, image: image, session: session)
        }
    }

    private static func tierMessage(for tier: TierState, image: UIImage?, session: MSSession?) -> MSMessage {
        let message = MSMessage(session: session ?? MSSession())

        let layout = MSMessageTemplateLayout()
        layout.image = image
        let caption = tier.title.isEmpty ? "Tier Chart" : tier.title
        layout.caption = caption
        layout.subcaption = tier.isFullyRanked
            ? "All ranked — tap to rearrange"
            : "\(tier.rankedItemCount) of \(tier.totalItemCount) ranked — tap to contribute"
        message.layout = layout

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "id", value: tier.id.uuidString),
            URLQueryItem(name: "kind", value: ChartKind.tier.rawValue)
        ]
        // P0: no completedDay/daily items for tiers — tier dailies are P2.
        message.url = components.url
        message.summaryText = tier.isFullyRanked
            ? "\(caption) is fully ranked!"
            : "Contribute to \(caption)"
        return message
    }

    /// Reads the `kind` query item. Absent or unrecognized values fall back to
    /// `.grid` so legacy and foreign URLs keep parsing exactly as before.
    static func chartKind(from message: MSMessage) -> ChartKind {
        guard let url = message.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let kindValue = components.queryItems?.first(where: { $0.name == "kind" })?.value
        else { return .grid }
        return kindValue == ChartKind.tier.rawValue ? .tier : .grid
    }

    /// False only when a `kind` item is present with a value this build does not
    /// recognize — the coordinator shows the update interstitial in that case.
    static func isKnownKind(from message: MSMessage) -> Bool {
        guard let url = message.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let kindValue = components.queryItems?.first(where: { $0.name == "kind" })?.value
        else { return true }
        return kindValue == ChartKind.grid.rawValue || kindValue == ChartKind.tier.rawValue
    }

    static func dailyCompletion(from message: MSMessage) -> DailyIdentity? {
        guard let url = message.url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let day = items.first(where: { $0.name == "completedDay" })?.value,
              let templateID = items.first(where: { $0.name == "templateID" })?.value,
              DailyCalendar.date(for: day) != nil, templateID == "daily-\(day)" else { return nil }
        return DailyIdentity(day: day, templateID: templateID)
    }

    static func chartID(from message: MSMessage) -> String? {
        guard let url = message.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return components.queryItems?.first(where: { $0.name == "id" })?.value
    }
}
