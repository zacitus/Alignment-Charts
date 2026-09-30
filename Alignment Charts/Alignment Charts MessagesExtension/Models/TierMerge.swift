import Foundation

/// Result of a three-way tier-chart merge: the merged chart plus any conflicts
/// that need the user's choices. Mirrors ChartMergeResult.
struct TierMergeResult: Sendable {
    var tier: TierState
    var conflicts: [ChartConflict]
}

/// A tier-chart merge that needs the user's conflict choices before it can be
/// shared. Mirrors ChartMergeReview.
struct TierMergeReview: Error, Identifiable, Sendable {
    let id = UUID()
    let base: TierState?
    let local: TierState
    let remote: TierState

    func merged(choices: [String: ChartConflictChoice] = [:]) -> TierMergeResult {
        TierMerge.merge(base: base, local: local, remote: remote, choices: choices)
    }
}

/// Three-way merge for tier charts, mirroring the grid's ChartMerge.
///
/// Item identity is global: every ChartCell id appears exactly once in the
/// merged chart, wherever it lands. Tier membership (which tier, or unranked)
/// is the mergeable location; within-tier order is merged separately so an
/// insertion that shifts indices never reads as a move. A merged tier count
/// outside 2...8 becomes a reviewable conflict; capacity overflow spills
/// losslessly to unranked (mirroring setTierCount); nothing else is ever
/// silently dropped or duplicated.
enum TierMerge {
    /// An item's merged fate: gone entirely, or placed with merged content.
    private enum ItemFate: Equatable {
        case gone
        case placed(cell: ChartCell, tierID: UUID?)
    }

    /// A tier's existence: removed, or kept. Field changes (label, color,
    /// items) never read as deletion; they merge separately below.
    private enum TierExistence: Equatable {
        case removed
        case kept
    }

    static func merge(base: TierState?, local: TierState, remote: TierState,
                      choices: [String: ChartConflictChoice] = [:]) -> TierMergeResult {
        var conflicts: [ChartConflict] = []

        /// Field-level pick, mirroring ChartMerge's helper: unchanged on one
        /// side wins, a missing choice records a conflict and keeps remote as
        /// a placeholder (a result with conflicts is never uploaded).
        func choose<T: Equatable>(_ original: T, _ mine: T, _ shared: T,
                                  id: String, title: String,
                                  preview: (T) -> ChartConflictPreview) -> T {
            if mine == shared { return mine }
            if mine == original { return shared }
            if shared == original { return mine }
            if let choice = choices[id] { return choice == .mine ? mine : shared }
            conflicts.append(ChartConflict(id: id, title: title,
                                           mine: preview(mine), shared: preview(shared)))
            return shared
        }

        /// Pick without a base (both sides added the same item, practically
        /// impossible with UUIDs): agreement wins, otherwise a choice or a
        /// recorded conflict. Unlike `choose`, passing one side as its own
        /// original would silently hand every field to the other side.
        func chooseAdded<T: Equatable>(_ mine: T, _ shared: T,
                                       id: String, title: String,
                                       preview: (T) -> ChartConflictPreview) -> T {
            if mine == shared { return mine }
            if let choice = choices[id] { return choice == .mine ? mine : shared }
            conflicts.append(ChartConflict(id: id, title: title,
                                           mine: preview(mine), shared: preview(shared)))
            return shared
        }

        // No ancestor: an older draft without a shared base cannot merge
        // field-by-field. Same policy as ChartMerge.
        guard let base else {
            if local.hasSameContent(as: remote) {
                return TierMergeResult(tier: remote, conflicts: [])
            }
            if let choice = choices["tierchart"] {
                var selected = choice == .mine ? local : remote
                selected.daily = remote.daily
                selected.schemaVersion = remote.schemaVersion
                return TierMergeResult(tier: selected, conflicts: [])
            }
            return TierMergeResult(tier: remote, conflicts: [ChartConflict(
                id: "tierchart",
                title: "This older draft needs review",
                mine: .tier(local),
                shared: .tier(remote))])
        }

        // MARK: - Tier list

        let baseOrder = base.tiers.map(\.id)
        let localOrder = local.tiers.map(\.id)
        let remoteOrder = remote.tiers.map(\.id)
        let baseIDs = Set(baseOrder)
        let localByID = Dictionary(uniqueKeysWithValues: local.tiers.map { ($0.id, $0) })
        let remoteByID = Dictionary(uniqueKeysWithValues: remote.tiers.map { ($0.id, $0) })
        let baseByID = Dictionary(uniqueKeysWithValues: base.tiers.map { ($0.id, $0) })

        /// Merged (label, color) for every surviving tier, in merged order.
        var mergedTiers: [(id: UUID, label: String, color: TierColor)] = []

        for id in baseOrder {
            // baseOrder derives from base.tiers, so the lookup cannot miss.
            guard let baseTier = baseByID[id] else { continue }
            let localTier = localByID[id]
            let remoteTier = remoteByID[id]
            // Existence merges on its own: a deletion only needs review when
            // the other side actually changed the tier (label, color, or
            // items). Independent label/color edits merge as fields below and
            // never surface a bogus deletion conflict.
            let mine: TierExistence = localTier == nil ? .removed : .kept
            let shared: TierExistence = remoteTier == nil ? .removed : .kept
            let existenceID = "tier-removed-\(id.uuidString)"
            let existence: TierExistence
            if mine == shared {
                existence = mine
            } else if mine == .removed, remoteTier == baseTier {
                existence = .removed
            } else if shared == .removed, localTier == baseTier {
                existence = .removed
            } else if let choice = choices[existenceID] {
                existence = choice == .mine ? mine : shared
            } else {
                conflicts.append(ChartConflict(
                    id: existenceID,
                    title: "Tier “\(baseTier.label)” was deleted on one side and changed on the other",
                    mine: mine == .removed ? .text("Deleted — its items move to Unranked") : .tier(local),
                    shared: shared == .removed ? .text("Deleted — its items move to Unranked") : .tier(remote)))
                existence = shared
            }
            switch existence {
            case .removed:
                continue
            case .kept:
                // A side that deleted the tier expresses no opinion on its
                // fields; the base value stands in so resolving the existence
                // conflict never conjures a second field conflict.
                let label = choose(baseTier.label,
                                   localTier?.label ?? baseTier.label,
                                   remoteTier?.label ?? baseTier.label,
                                   id: "tier-\(id.uuidString)-label",
                                   title: "Tier label (was “\(baseTier.label)”)",
                                   preview: { .text($0.isEmpty ? "(empty)" : $0) })
                let mergedColor = mergeColor(base: baseTier.color,
                                             local: localTier?.color ?? baseTier.color,
                                             remote: remoteTier?.color ?? baseTier.color,
                                             id: id, conflicts: &conflicts, choices: choices,
                                             localChart: local, remoteChart: remote)
                mergedTiers.append((id: id, label: label, color: mergedColor))
            }
        }

        // Tiers added by either side (a UUID collision is practically
        // impossible; the local one wins defensively).
        for tier in local.tiers where !baseIDs.contains(tier.id) {
            mergedTiers.append((id: tier.id, label: tier.label, color: tier.color))
        }
        for tier in remote.tiers where !baseIDs.contains(tier.id) && localByID[tier.id] == nil {
            mergedTiers.append((id: tier.id, label: tier.label, color: tier.color))
        }

        // Merged tier order: an unchanged side defers to the side that
        // reordered; reorders on both sides need the user's pick. Only base
        // tiers participate: added tiers are appended below in each side's
        // own order, so adding a tier never reads as a reorder.
        let survivingIDs = Set(mergedTiers.map(\.id))
        let baseSurvivors = baseOrder.filter { survivingIDs.contains($0) }
        let localBaseSurvivors = localOrder.filter { baseIDs.contains($0) && survivingIDs.contains($0) }
        let remoteBaseSurvivors = remoteOrder.filter { baseIDs.contains($0) && survivingIDs.contains($0) }
        let order: [UUID]
        if localBaseSurvivors == baseSurvivors && remoteBaseSurvivors == baseSurvivors {
            order = baseSurvivors
        } else if localBaseSurvivors == baseSurvivors {
            order = remoteBaseSurvivors
        } else if remoteBaseSurvivors == baseSurvivors {
            order = localBaseSurvivors
        } else if localBaseSurvivors == remoteBaseSurvivors {
            order = localBaseSurvivors
        } else if let choice = choices["tier-order"] {
            order = (choice == .mine ? localBaseSurvivors : remoteBaseSurvivors)
        } else {
            conflicts.append(ChartConflict(id: "tier-order", title: "Tier order",
                                           mine: .tier(local), shared: .tier(remote)))
            order = remoteBaseSurvivors
        }
        // Added tiers keep each side's own relative order, local first.
        let addedLocal = localOrder.filter { !baseIDs.contains($0) && survivingIDs.contains($0) }
        let addedRemote = remoteOrder.filter { !baseIDs.contains($0) && survivingIDs.contains($0) && !addedLocal.contains($0) }
        let mergedOrder = order + addedLocal + addedRemote
        let mergedTierByID = Dictionary(uniqueKeysWithValues: mergedTiers.map { ($0.id, $0) })

        // Structural check up front: a merged tier count outside 2...8 cannot
        // be reconciled field-by-field, so the whole chart goes to review.
        if !(TierState.tierCountRange.contains(mergedOrder.count)) {
            if let choice = choices["tier-structure"] {
                var selected = choice == .mine ? local : remote
                selected.daily = remote.daily
                selected.schemaVersion = remote.schemaVersion
                return TierMergeResult(tier: selected, conflicts: [])
            }
            return TierMergeResult(tier: remote, conflicts: [ChartConflict(
                id: "tier-structure",
                title: "Tier count",
                mine: .tier(local),
                shared: .tier(remote))])
        }

        // MARK: - Items (global identity, exactly once)

        /// id -> (cell, tierID); tierID nil means unranked.
        func index(_ tier: TierState) -> [UUID: (cell: ChartCell, tierID: UUID?)] {
            var result: [UUID: (ChartCell, UUID?)] = [:]
            for t in tier.tiers {
                for item in t.items { result[item.id] = (item, t.id) }
            }
            for item in tier.unranked { result[item.id] = (item, nil) }
            return result
        }
        let baseItems = index(base)
        let localItems = index(local)
        let remoteItems = index(remote)

        func caption(of cell: ChartCell?) -> String {
            guard let cell, !cell.caption.isEmpty else { return "An item" }
            return "“\(cell.caption)”"
        }

        /// tierID -> label for move-conflict previews.
        func tierLabel(_ tierID: UUID?) -> String {
            guard let tierID else { return "Unranked" }
            return mergedTierByID[tierID]?.label.isEmpty == false
                ? mergedTierByID[tierID]!.label
                : "(removed tier)"
        }

        var fates: [UUID: ItemFate] = [:]
        for id in Set(baseItems.keys).union(localItems.keys).union(remoteItems.keys) {
            let b = baseItems[id]
            let l = localItems[id]
            let r = remoteItems[id]
            let titleBase = caption(of: b?.cell ?? l?.cell ?? r?.cell)

            switch (b, l, r) {
            case (nil, nil, nil):
                continue
            case (_, nil, nil):
                // Deleted on both sides.
                continue
            case (let bb?, nil, let rr?):
                // Deleted locally.
                let original = ItemFate.placed(cell: bb.cell, tierID: bb.tierID)
                let shared = ItemFate.placed(cell: rr.cell, tierID: rr.tierID)
                fates[id] = choose(original, .gone, shared,
                                    id: "item-removed-\(id.uuidString)",
                                    title: "\(titleBase) was deleted here but changed in the shared version",
                                    preview: {
                                        switch $0 {
                                        case .gone: return .text("Deleted")
                                        case .placed: return .tier(remote)
                                        }
                                    })
            case (let bb?, let ll?, nil):
                // Deleted remotely; mirror of the above.
                let original = ItemFate.placed(cell: bb.cell, tierID: bb.tierID)
                let mine = ItemFate.placed(cell: ll.cell, tierID: ll.tierID)
                fates[id] = choose(original, mine, .gone,
                                    id: "item-removed-\(id.uuidString)",
                                    title: "\(titleBase) was deleted in the shared version but changed here",
                                    preview: {
                                        switch $0 {
                                        case .gone: return .text("Deleted")
                                        case .placed: return .tier(local)
                                        }
                                    })
            case (nil, let ll?, nil):
                fates[id] = .placed(cell: ll.cell, tierID: ll.tierID)
            case (nil, nil, let rr?):
                fates[id] = .placed(cell: rr.cell, tierID: rr.tierID)
            case (nil, let ll?, let rr?):
                // Added on both sides (practically impossible with UUIDs):
                // no base exists, so fields merge by agreement or choice.
                var mergedCell = ll.cell
                mergedCell.caption = chooseAdded(ll.cell.caption, rr.cell.caption,
                                                 id: "item-\(id.uuidString)-caption",
                                                 title: "\(titleBase) text",
                                                 preview: { .text($0.isEmpty ? "(empty)" : $0) })
                let addedImage = chooseAdded(ll.cell.imageReference, rr.cell.imageReference,
                                             id: "item-\(id.uuidString)-image",
                                             title: "\(titleBase) photo",
                                             preview: { .image($0) })
                if mergedCell.imageReference != addedImage { mergedCell.setImageReference(addedImage) }
                let addedTierID = chooseAdded(ll.tierID, rr.tierID,
                                              id: "item-\(id.uuidString)-moved",
                                              title: "\(titleBase) location",
                                              preview: { .text(tierLabel($0)) })
                fates[id] = .placed(cell: mergedCell, tierID: addedTierID)
            case (let bb?, let ll?, let rr?):
                // Present on both sides: merge caption and photo field by
                // field, then merge the location separately.
                let mergedCaption = choose(bb.cell.caption, ll.cell.caption, rr.cell.caption,
                                           id: "item-\(id.uuidString)-caption",
                                           title: "\(titleBase) text",
                                           preview: { .text($0.isEmpty ? "(empty)" : $0) })
                var mergedCell = ll.cell
                mergedCell.caption = mergedCaption
                let image = choose(bb.cell.imageReference, ll.cell.imageReference, rr.cell.imageReference,
                                   id: "item-\(id.uuidString)-image",
                                   title: "\(titleBase) photo",
                                   preview: { .image($0) })
                // Keep legacy encoding unchanged unless the reference actually
                // changes, mirroring the grid merge: swapping the photo
                // replaces the stored reference, never edits an asset in place.
                if mergedCell.imageReference != image { mergedCell.setImageReference(image) }
                let tierID = choose(bb.tierID, ll.tierID, rr.tierID,
                                    id: "item-\(id.uuidString)-moved",
                                    title: "\(titleBase) location",
                                    preview: { .text(tierLabel($0)) })
                fates[id] = .placed(cell: mergedCell, tierID: tierID)
            }
        }

        // MARK: - Assemble

        // Items whose tier did not survive the tier merge spill to unranked.
        var placed: [UUID: (cell: ChartCell, tierID: UUID?)] = [:]
        for (id, fate) in fates {
            switch fate {
            case .gone:
                continue
            case .placed(let cell, var tierID):
                if let id = tierID, mergedTierByID[id] == nil {
                    tierID = nil
                }
                placed[id] = (cell, tierID)
            }
        }

        /// Sequence of item ids in one list on one side.
        func rawSequence(_ tier: TierState, tierID: UUID?) -> [UUID] {
            if let tierID {
                return tier.tiers.first(where: { $0.id == tierID })?.items.map(\.id) ?? []
            }
            return tier.unranked.map(\.id)
        }

        /// Merged item order for one list: an unchanged side defers to the
        /// side that reordered; brand-new items keep each side's own order.
        /// Pure index shifts from insertions are not moves, so they never
        /// conflict here.
        func mergedSequence(tierID: UUID?) -> [UUID] {
            func isHere(_ id: UUID) -> Bool {
                guard let entry = placed[id] else { return false }
                return entry.tierID == tierID
            }
            let baseRaw = rawSequence(base, tierID: tierID)
            let baseSeq = baseRaw.filter(isHere)
            let localSeq = rawSequence(local, tierID: tierID).filter(isHere)
            let remoteSeq = rawSequence(remote, tierID: tierID).filter(isHere)
            let listID = tierID?.uuidString ?? "unranked"
            // Whether each side preserved the base relative order (appending
            // new items is not a reorder).
            let localKeepsOrder = localSeq.filter { baseRaw.contains($0) } == baseSeq
            let remoteKeepsOrder = remoteSeq.filter { baseRaw.contains($0) } == baseSeq
            let ordered: [UUID]
            if localSeq == baseSeq && remoteSeq == baseSeq {
                ordered = baseSeq
            } else if localSeq == baseSeq {
                ordered = remoteSeq
            } else if remoteSeq == baseSeq {
                ordered = localSeq
            } else if localSeq == remoteSeq {
                ordered = localSeq
            } else if localKeepsOrder && remoteKeepsOrder {
                // Both sides only appended new items; concatenate them after
                // the base order without a conflict.
                ordered = baseSeq
            } else if let choice = choices["order-\(listID)"] {
                ordered = (choice == .mine ? localSeq : remoteSeq)
            } else {
                conflicts.append(ChartConflict(id: "order-\(listID)", title: "Item order",
                                               mine: .tier(local), shared: .tier(remote)))
                ordered = remoteSeq
            }
            // Items new to this list keep local-then-remote order.
            var seen = Set(ordered)
            var result = ordered
            // Items retained by conflict resolution (e.g. kept after a
            // delete-vs-edit choice) may be absent from the winning side's
            // sequence; they rejoin in base order rather than being dropped.
            for id in baseRaw where isHere(id) && seen.insert(id).inserted {
                result.append(id)
            }
            for id in localSeq where !baseRaw.contains(id) && seen.insert(id).inserted {
                result.append(id)
            }
            for id in remoteSeq where !baseRaw.contains(id) && seen.insert(id).inserted {
                result.append(id)
            }
            return result
        }

        // Capacity spill, mirroring setTierCount: a tier that would exceed its
        // cap keeps its first 24 merged items; the rest move to unranked
        // rather than being dropped.
        var spill: [UUID] = []
        var tiers: [Tier] = []
        for id in mergedOrder {
            guard let info = mergedTierByID[id] else { continue }
            var ids = mergedSequence(tierID: id)
            if ids.count > TierState.maxItemsPerTier {
                spill.append(contentsOf: ids[TierState.maxItemsPerTier...])
                ids = Array(ids[..<TierState.maxItemsPerTier])
            }
            tiers.append(Tier(id: id, label: info.label, color: info.color,
                              items: ids.compactMap { placed[$0]?.cell }))
        }
        var unrankedIDs = mergedSequence(tierID: nil)
        // Items spilled from dropped tiers join unranked after the merged
        // unranked items, in dropped-tier order for determinism.
        for id in baseOrder where !survivingIDs.contains(id) {
            for item in base.tiers.first(where: { $0.id == id })?.items ?? [] {
                if let entry = placed[item.id], entry.tierID == nil, !unrankedIDs.contains(item.id) {
                    unrankedIDs.append(item.id)
                }
            }
        }
        // Any other surviving item assigned to unranked (e.g. added by one
        // side into a tier the other side removed) joins unranked in a
        // deterministic local-then-remote order rather than disappearing.
        for source in [local, remote] {
            let candidates = source.unranked.map(\.id) + source.tiers.flatMap { $0.items.map(\.id) }
            for id in candidates {
                if let entry = placed[id], entry.tierID == nil, !unrankedIDs.contains(id) {
                    unrankedIDs.append(id)
                }
            }
        }
        unrankedIDs.append(contentsOf: spill.filter { !unrankedIDs.contains($0) })
        let unranked = unrankedIDs.compactMap { placed[$0]?.cell }

        var merged = TierState(
            id: remote.id,
            title: choose(base.title, local.title, remote.title,
                          id: "title", title: "Chart title",
                          preview: { .text($0.isEmpty ? "(untitled)" : $0) }),
            updatedAt: max(local.updatedAt, remote.updatedAt),
            tiers: tiers,
            unranked: unranked)
        merged.daily = remote.daily
        // Carry the schema forward like the grid merge does by starting from
        // remote; a fresh initializer would silently reset it.
        merged.schemaVersion = remote.schemaVersion
        // By construction only capacity overflow can still be invalid here:
        // the tier count went to review above and item ids are unique. Route
        // it to review as a whole-chart pick rather than dead-ending the
        // share with an unresolvable error.
        if !merged.isValid {
            if let choice = choices["tier-capacity"] {
                var selected = choice == .mine ? local : remote
                selected.daily = remote.daily
                selected.schemaVersion = remote.schemaVersion
                return TierMergeResult(tier: selected, conflicts: [])
            }
            return TierMergeResult(tier: remote, conflicts: [ChartConflict(
                id: "tier-capacity",
                title: "Too many items",
                mine: .tier(local),
                shared: .tier(remote))])
        }
        return TierMergeResult(tier: merged, conflicts: conflicts)
    }

    // MARK: - Helpers

    /// Tier color merge with whole-chart previews, so the difference is
    /// visible (a color has no meaningful text preview).
    private static func mergeColor(base: TierColor, local: TierColor, remote: TierColor,
                                   id: UUID,
                                   conflicts: inout [ChartConflict],
                                   choices: [String: ChartConflictChoice],
                                   localChart: TierState, remoteChart: TierState) -> TierColor {
        if local == remote { return local }
        if local == base { return remote }
        if remote == base { return local }
        let key = "tier-\(id.uuidString)-color"
        if let choice = choices[key] { return choice == .mine ? local : remote }
        conflicts.append(ChartConflict(id: key, title: "Tier color",
                                       mine: .tier(localChart), shared: .tier(remoteChart)))
        return remote
    }
}
