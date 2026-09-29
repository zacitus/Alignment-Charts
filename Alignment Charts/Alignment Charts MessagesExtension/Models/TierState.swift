import SwiftUI
import Foundation

/// An RGB color that survives Codable round-trips; `Color` itself does not conform.
struct TierColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    func swiftUIColor() -> Color {
        Color(red: red, green: green, blue: blue)
    }

    /// Okabe-Ito colorblind-safe palette (Okabe & Ito, 2008), with the traditional
    /// black swapped for a neutral gray so it stays visible against dark chrome.
    ///   orange          #E69F00
    ///   sky blue        #56B4E9
    ///   bluish green    #009E73
    ///   yellow          #F0E442
    ///   blue            #0072B2
    ///   vermillion      #D55E00
    ///   reddish purple  #CC79A7
    ///   gray            #999999
    static let defaultPalette: [TierColor] = [
        TierColor(red: 0.9020, green: 0.6235, blue: 0.0000),
        TierColor(red: 0.3373, green: 0.7059, blue: 0.9137),
        TierColor(red: 0.0000, green: 0.6196, blue: 0.4510),
        TierColor(red: 0.9412, green: 0.8941, blue: 0.2588),
        TierColor(red: 0.0000, green: 0.4471, blue: 0.6980),
        TierColor(red: 0.8353, green: 0.3686, blue: 0.0000),
        TierColor(red: 0.8000, green: 0.4745, blue: 0.6549),
        TierColor(red: 0.6000, green: 0.6000, blue: 0.6000),
    ]
}

struct Tier: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var label: String
    var color: TierColor
    var items: [ChartCell]
}

struct TierState: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String = ""
    var updatedAt: Date = .now
    var daily: DailyIdentity? = nil
    var schemaVersion: Int = 1
    var tiers: [Tier]
    var unranked: [ChartCell]

    static let tierCountRange = 2...8
    static let maxItemsPerTier = 24
    static let maxUnrankedItems = 48
    static let maxTotalItems = 100

    static func makeDefault() -> TierState {
        let labels = ["S", "A", "B", "C", "D", "F"]
        let tiers = labels.enumerated().map { index, label in
            Tier(label: label, color: TierColor.defaultPalette[index], items: [])
        }
        return TierState(tiers: tiers, unranked: [])
    }

    /// Timestamps and schema bumps describe activity, not whether the user changed chart content.
    func hasSameContent(as other: TierState) -> Bool {
        var lhs = self
        var rhs = other
        lhs.updatedAt = .distantPast
        rhs.updatedAt = .distantPast
        lhs.schemaVersion = 0
        rhs.schemaVersion = 0
        return lhs == rhs
    }

    var isValid: Bool {
        guard Self.tierCountRange.contains(tiers.count) else { return false }
        guard Set(tiers.map(\.id)).count == tiers.count else { return false }
        guard tiers.allSatisfy({ $0.items.count <= Self.maxItemsPerTier }) else { return false }
        guard unranked.count <= Self.maxUnrankedItems else { return false }
        let allItemIDs = tiers.flatMap { $0.items.map(\.id) } + unranked.map(\.id)
        guard Set(allItemIDs).count == allItemIDs.count else { return false }
        guard allItemIDs.count <= Self.maxTotalItems else { return false }
        return true
    }

    var rankedItemCount: Int { tiers.reduce(0) { $0 + $1.items.count } }
    var totalItemCount: Int { rankedItemCount + unranked.count }
    var isFullyRanked: Bool { unranked.isEmpty && totalItemCount > 0 }

    /// Removing a tier deletes a container, never user content — spilled items land in `unranked`.
    mutating func setTierCount(_ n: Int) {
        let target = min(max(n, Self.tierCountRange.lowerBound), Self.tierCountRange.upperBound)
        guard target != tiers.count else { return }
        if target < tiers.count {
            while tiers.count > target {
                let removed = tiers.removeLast()
                unranked.append(contentsOf: removed.items)
            }
        } else {
            while tiers.count < target {
                let color = TierColor.defaultPalette[tiers.count % TierColor.defaultPalette.count]
                tiers.append(Tier(label: "", color: color, items: []))
            }
        }
    }

    @discardableResult
    mutating func addTier(label: String, color: TierColor) -> Bool {
        guard tiers.count < Self.tierCountRange.upperBound else { return false }
        tiers.append(Tier(label: label, color: color, items: []))
        return true
    }

    @discardableResult
    mutating func removeTier(id: UUID) -> Bool {
        guard tiers.count > Self.tierCountRange.lowerBound else { return false }
        guard let index = tiers.firstIndex(where: { $0.id == id }) else { return false }
        let removed = tiers.remove(at: index)
        unranked.append(contentsOf: removed.items)
        return true
    }

    mutating func moveTier(from: Int, to: Int) {
        guard tiers.indices.contains(from) else { return }
        let tier = tiers.remove(at: from)
        let target = min(max(to, 0), tiers.count)
        tiers.insert(tier, at: target)
    }

    mutating func renameTier(id: UUID, label: String) {
        guard let index = tiers.firstIndex(where: { $0.id == id }) else { return }
        tiers[index].label = label
    }

    mutating func setTierColor(id: UUID, color: TierColor) {
        guard let index = tiers.firstIndex(where: { $0.id == id }) else { return }
        tiers[index].color = color
    }

    /// `tierIndex` nil means either "in `unranked`" or "not found"; check `itemIndex >= 0`
    /// to distinguish (a not-found item reports `itemIndex == -1`).
    func locate(_ id: UUID) -> (tierIndex: Int?, itemIndex: Int) {
        for (tierIndex, tier) in tiers.enumerated() {
            if let itemIndex = tier.items.firstIndex(where: { $0.id == id }) {
                return (tierIndex, itemIndex)
            }
        }
        if let itemIndex = unranked.firstIndex(where: { $0.id == id }) {
            return (nil, itemIndex)
        }
        return (nil, -1)
    }

    /// `tierID` nil targets `unranked`. Validates capacity before removing the item from its
    /// current location, so a rejected move never loses the item.
    @discardableResult
    mutating func moveItem(id: UUID, toTier tierID: UUID?, at index: Int?) -> Bool {
        let location = locate(id)
        guard location.itemIndex >= 0 else { return false }

        if let tierID {
            guard let destIndex = tiers.firstIndex(where: { $0.id == tierID }) else { return false }
            let isSameTier = location.tierIndex == destIndex
            let effectiveCount = isSameTier ? tiers[destIndex].items.count - 1 : tiers[destIndex].items.count
            guard effectiveCount < Self.maxItemsPerTier else { return false }

            let item: ChartCell
            if let sourceTierIndex = location.tierIndex {
                item = tiers[sourceTierIndex].items.remove(at: location.itemIndex)
            } else {
                item = unranked.remove(at: location.itemIndex)
            }
            let insertAt = Self.clampedInsertIndex(index, count: tiers[destIndex].items.count)
            tiers[destIndex].items.insert(item, at: insertAt)
        } else {
            let isSameDestination = location.tierIndex == nil
            let effectiveCount = isSameDestination ? unranked.count - 1 : unranked.count
            guard effectiveCount < Self.maxUnrankedItems else { return false }

            let item: ChartCell
            if let sourceTierIndex = location.tierIndex {
                item = tiers[sourceTierIndex].items.remove(at: location.itemIndex)
            } else {
                item = unranked.remove(at: location.itemIndex)
            }
            let insertAt = Self.clampedInsertIndex(index, count: unranked.count)
            unranked.insert(item, at: insertAt)
        }
        return true
    }

    @discardableResult
    mutating func removeItem(id: UUID) -> Bool {
        let location = locate(id)
        guard location.itemIndex >= 0 else { return false }
        if let tierIndex = location.tierIndex {
            tiers[tierIndex].items.remove(at: location.itemIndex)
        } else {
            unranked.remove(at: location.itemIndex)
        }
        return true
    }

    private static func clampedInsertIndex(_ index: Int?, count: Int) -> Int {
        guard let index, index >= 0, index <= count else { return count }
        return index
    }
}
