import Foundation

enum ChartKind: String, Codable, Sendable {
    case grid
    case tier
}

/// A grid chart and a tier chart are siblings, not variants of one shape: grids are dense and
/// fixed-size, tier charts are sparse and ragged. Keeping them as separate payload types (instead
/// of one struct with half its fields meaningless per kind) keeps validation and merge logic sane.
enum ChartContent: Equatable, Sendable {
    case grid(ChartState)
    case tier(TierState)
}

extension ChartContent: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, grid, tier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(ChartKind.self, forKey: .kind)
        switch kind {
        case .grid:
            self = .grid(try container.decode(ChartState.self, forKey: .grid))
        case .tier:
            self = .tier(try container.decode(TierState.self, forKey: .tier))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .grid(let chart):
            try container.encode(ChartKind.grid, forKey: .kind)
            try container.encode(chart, forKey: .grid)
        case .tier(let tier):
            try container.encode(ChartKind.tier, forKey: .kind)
            try container.encode(tier, forKey: .tier)
        }
    }
}

extension ChartContent: Identifiable {
    var id: UUID {
        switch self {
        case .grid(let chart): return chart.id
        case .tier(let tier): return tier.id
        }
    }
}

extension ChartContent {
    var kind: ChartKind {
        switch self {
        case .grid: return .grid
        case .tier: return .tier
        }
    }

    var title: String {
        switch self {
        case .grid(let chart): return chart.title
        case .tier(let tier): return tier.title
        }
    }

    var updatedAt: Date {
        switch self {
        case .grid(let chart): return chart.updatedAt
        case .tier(let tier): return tier.updatedAt
        }
    }

    var isValid: Bool {
        switch self {
        case .grid(let chart): return chart.isValid
        case .tier(let tier): return tier.isValid
        }
    }

    /// Cross-kind content is never equal, even if a grid and a tier chart share an id.
    func hasSameContent(as other: ChartContent) -> Bool {
        switch (self, other) {
        case (.grid(let lhs), .grid(let rhs)):
            return lhs.hasSameContent(as: rhs)
        case (.tier(let lhs), .tier(let rhs)):
            return lhs.hasSameContent(as: rhs)
        default:
            return false
        }
    }

    func withUpdatedAt(_ date: Date) -> ChartContent {
        switch self {
        case .grid(var chart):
            chart.updatedAt = date
            return .grid(chart)
        case .tier(var tier):
            tier.updatedAt = date
            return .tier(tier)
        }
    }
}
