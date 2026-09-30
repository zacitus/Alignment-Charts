import Foundation

private enum TestFailure: Error { case network }

@main
struct CollaborationTests {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fatalError("FAILED: \(message)") }
    }

    static func main() async throws {
        let base = ChartState()
        var mine = base
        var shared = base
        mine.cells[0].caption = "Alice"
        shared.cells[8].caption = "Bob"
        var result = ChartMerge.merge(base: base, local: mine, remote: shared)
        expect(result.conflicts.isEmpty, "different cells merge")
        expect(result.chart.cells[0].caption == "Alice" && result.chart.cells[8].caption == "Bob", "both contributions survive")

        mine = base
        shared = base
        let photoA = UUID()
        let photoB = UUID()
        mine.cells[0].caption = "Caption"
        shared.cells[0].setImageReference(photoA)
        result = ChartMerge.merge(base: base, local: mine, remote: shared)
        expect(result.conflicts.isEmpty, "text and photo in same cell merge")
        expect(result.chart.cells[0].caption == "Caption" && result.chart.cells[0].imageReference == photoA, "same-cell independent fields survive")

        mine = base
        shared = base
        mine.title = "Mine"
        shared.title = "Theirs"
        mine.cells[0].caption = "Local contribution"
        shared.cells[1].caption = "Remote contribution"
        result = ChartMerge.merge(base: base, local: mine, remote: shared)
        expect(result.conflicts.map(\.id) == ["title"], "same-field conflict requires review")
        result = ChartMerge.merge(base: base, local: mine, remote: shared, choices: ["title": .mine])
        expect(result.conflicts.isEmpty && result.chart.title == "Mine", "local resolution is applied")
        expect(result.chart.cells[0].caption == mine.cells[0].caption && result.chart.cells[1].caption == shared.cells[1].caption, "resolution retains nonconflicting changes")
        let resolved = result.chart
        var newer = shared
        newer.title = "Third edit"
        expect(!ChartMerge.merge(base: shared, local: resolved, remote: newer).conflicts.isEmpty, "resolution does not authorize overwriting a newer change")
        result = ChartMerge.merge(base: base, local: mine, remote: shared, choices: ["title": .shared])
        expect(result.chart.title == "Theirs", "remote resolution is applied")

        mine = base
        shared = base
        mine.cells[0].setImageReference(photoA)
        shared.cells[0].setImageReference(photoB)
        result = ChartMerge.merge(base: base, local: mine, remote: shared)
        expect(result.conflicts.count == 1, "different replacement images conflict despite both having hasImage=true")
        result = ChartMerge.merge(base: base, local: mine, remote: shared, choices: [result.conflicts[0].id: .mine])
        expect(result.chart.cells[0].imageReference == photoA, "photo resolution uses the selected immutable asset")
        var imageBase = base
        imageBase.cells[0].setImageReference(photoA)
        mine = imageBase
        shared = imageBase
        mine.cells[0].setImageReference(nil)
        shared.cells[0].setImageReference(photoB)
        expect(ChartMerge.merge(base: imageBase, local: mine, remote: shared).conflicts.count == 1, "remove versus replace photo conflicts")

        mine = base
        shared = base
        mine.rowLabels[0] = "Good"
        shared.columnLabels[1] = "Neutral"
        shared.rowAxisTitle = "Morality"
        result = ChartMerge.merge(base: base, local: mine, remote: shared)
        expect(result.conflicts.isEmpty && result.chart.rowLabels[0] == "Good" && result.chart.columnLabels[1] == "Neutral" && result.chart.rowAxisTitle == "Morality", "labels and axis fields merge separately")

        for localResize in [true, false] {
            var resized = base
            resized.setRows(2)
            var edited = base
            edited.cells[0].caption = "Retained"
            result = ChartMerge.merge(base: base, local: localResize ? resized : edited, remote: localResize ? edited : resized)
            expect(result.conflicts.isEmpty && result.chart.rows == 2 && result.chart.cells[0].caption == "Retained", "resize preserves edits to retained cells in either direction")
            edited.cells[8].caption = "Must not disappear"
            result = ChartMerge.merge(base: base, local: localResize ? resized : edited, remote: localResize ? edited : resized)
            expect(result.conflicts.map(\.id) == ["grid"], "deleting an edited cell requires a grid choice")
            edited = base
            edited.rowLabels[2] = "Must not disappear"
            expect(ChartMerge.merge(base: base, local: localResize ? resized : edited, remote: localResize ? edited : resized).conflicts.count == 1, "deleting an edited row label conflicts")
        }
        mine = base
        shared = base
        mine.setColumns(4)
        mine.cells[3].caption = "New column"
        shared.cells[3].caption = "Row two"
        result = ChartMerge.merge(base: base, local: mine, remote: shared)
        expect(result.conflicts.isEmpty && result.chart.cells[3].caption == "New column" && result.chart.cells[4].caption == "Row two", "column insertion merges by stable cell ID, not array offset")
        shared.setRows(4)
        result = ChartMerge.merge(base: base, local: mine, remote: shared)
        expect(result.conflicts.map(\.id) == ["grid"], "incompatible concurrent layouts require review")
        result = ChartMerge.merge(base: base, local: mine, remote: shared, choices: ["grid": .shared])
        expect(result.conflicts.isEmpty && result.chart.cells == shared.cells && result.chart.rows == 4, "grid choice keeps consistent geometry")

        mine = base
        mine.title = "Same"
        shared = mine
        expect(ChartMerge.merge(base: base, local: mine, remote: shared).conflicts.isEmpty, "identical concurrent changes need no review")
        shared.updatedAt = .distantFuture
        expect(mine.hasSameContent(as: shared), "timestamp changes are not user edits")
        expect(ChartMerge.merge(base: nil, local: mine, remote: shared).conflicts.isEmpty, "matching legacy draft is safe")
        expect(ChartMerge.merge(base: nil, local: base, remote: shared).conflicts.map(\.id) == ["chart"], "unknown ancestor never silently overwrites")
        let legacyData = try JSONSerialization.data(withJSONObject: ["id": UUID().uuidString, "caption": "Old", "hasImage": true])
        let legacy = try JSONDecoder().decode(ChartCell.self, from: legacyData)
        expect(legacy.imageID == nil && legacy.imageReference == legacy.id, "old photos remain readable")
        expect(tryDecode(legacy), "versioned model round trips old records")

        // Exhaustively check no-op merge behavior across all supported dimensions.
        for rows in ChartState.sizeRange {
            for columns in ChartState.sizeRange {
                var changed = base
                changed.setRows(rows)
                changed.setColumns(columns)
                changed.cells[changed.cells.count - 1].caption = "Last cell"
                for reverse in [false, true] {
                    let merge = ChartMerge.merge(base: base, local: reverse ? changed : base, remote: reverse ? base : changed)
                    expect(merge.conflicts.isEmpty && merge.chart.hasSameContent(as: changed) && merge.chart.isValid, "unchanged editor preserves all remote dimensions")
                }
            }
        }
        try await testSaveRaces(base)
        try testDraftPersistence()
        try testTierContentPayload()
        print("PASS: \(checks) collaboration checks")
    }

    static func tryDecode(_ cell: ChartCell) -> Bool {
        (try? JSONDecoder().decode(ChartCell.self, from: JSONEncoder().encode(cell))) == cell
    }

    static func testSaveRaces(_ base: ChartState) async throws {
        var mine = base
        mine.cells[0].caption = "Mine"
        var server = base
        var version = 0
        var attempts = 0
        let saved = try await ChartSync.save(local: mine, base: base) {
            ChartSnapshot(chart: server, version: version)
        } commit: { chart, expected in
            attempts += 1
            if attempts == 1 {
                server.cells[8].caption = "Racing save"
                version += 1
            }
            guard expected == version else { throw ChartSyncError.recordChanged }
            server = chart
            version += 1
        }
        expect(attempts == 2, "stale server version triggers retry")
        expect(saved.cells[0].caption == "Mine" && saved.cells[8].caption == "Racing save", "retry merges racing contribution with original local edits")
        expect(saved.hasSameContent(as: server), "returned preview source equals committed chart")

        server = base
        attempts = 0
        do {
            _ = try await ChartSync.save(local: mine, base: base) {
                ChartSnapshot(chart: server, version: 0)
            } commit: { _, _ in
                attempts += 1
                server.cells[0].caption = "New conflicting edit"
                throw ChartSyncError.recordChanged
            }
            fatalError("Expected review")
        } catch let review as ChartMergeReview {
            expect(attempts == 1 && review.remote.cells[0].caption == "New conflicting edit", "conflict discovered on retry stops writes")
        }

        attempts = 0
        do {
            _ = try await ChartSync.save(local: mine, base: base) {
                ChartSnapshot(chart: base, version: 0)
            } commit: { _, _ in
                attempts += 1
                throw ChartSyncError.recordChanged
            }
            fatalError("Expected busy")
        } catch ChartSyncError.busy {
            expect(attempts == 5, "contention retries are bounded")
        }

        var commits = 0
        do {
            _ = try await ChartSync.save(local: mine, base: base, load: { () -> ChartSnapshot<Int>? in
                throw TestFailure.network
            }, commit: { _, _ in commits += 1 })
            fatalError("Expected network failure")
        } catch TestFailure.network {
            expect(commits == 0, "fetch failure never creates a replacement record")
        }
        do {
            _ = try await ChartSync.save(local: mine, base: base, load: { () -> ChartSnapshot<Int>? in nil }, commit: { _, _ in commits += 1 })
            fatalError("Expected missing chart")
        } catch ChartSyncError.missingChart {
            expect(commits == 0, "deleted shared chart is not recreated from stale data")
        }
        let created = try await ChartSync.save(local: mine, base: nil, load: { () -> ChartSnapshot<Int>? in nil }) { _, version in
            expect(version == nil, "new chart has no prior server version")
            commits += 1
        }
        expect(commits == 1 && created.hasSameContent(as: mine), "new chart can be created")
        attempts = 0
        do {
            _ = try await ChartSync.save(local: mine, base: base, load: { ChartSnapshot(chart: base, version: 0) }) { _, _ in
                attempts += 1
                throw TestFailure.network
            }
            fatalError("Expected failed commit")
        } catch TestFailure.network {
            expect(attempts == 1, "unknown commit outcome isn't automatically repeated")
        }
        var invalid = base
        invalid.cells.removeLast()
        do {
            _ = try await ChartSync.save(local: invalid, base: base, load: { ChartSnapshot(chart: base, version: 0) }, commit: { _, _ in fatalError("Invalid write") })
            fatalError("Expected invalid chart")
        } catch ChartSyncError.invalidChart {
            expect(true, "invalid layouts are rejected before merging")
        }
    }

    static func testDraftPersistence() throws {
        let base = ChartState()
        let scope = "collaboration-test-\(UUID())"
        defer { ChartHistoryStore.delete(base.id) }
        var draft = base
        draft.cells[0].caption = "Unsent edit"
        ChartHistoryStore.save(draft, base: base, in: scope)
        expect(ChartHistoryStore.baseline(for: base.id) == base, "editing ancestor survives disk round trip")
        var incoming = base
        incoming.cells[8].caption = "Received contribution"
        ChartHistoryStore.receive(incoming, in: scope)
        expect(ChartHistoryStore.pendingDraft(for: base.id)?.chart == draft, "incoming message preserves unsent draft")
        expect(ChartHistoryStore.baseline(for: base.id) == base, "incoming message preserves original editing ancestor")
        ChartHistoryStore.save(incoming, base: incoming, in: scope)
        expect(ChartHistoryStore.pendingDraft(for: base.id) == nil, "successful save marks draft clean")
        incoming.title = "New update"
        ChartHistoryStore.receive(incoming, in: scope)
        expect(ChartHistoryStore.baseline(for: base.id) == incoming, "clean history accepts incoming chart")
        // Exercise the actual old history format: no baseline field.
        let data = try JSONSerialization.data(withJSONObject: [
            "chart": JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)),
            "conversationScopes": [scope]
        ])
        try data.write(to: ChartHistoryStore.directory.appendingPathComponent(base.id.uuidString + ".json"))
        ChartHistoryStore.receive(incoming, in: scope)
        expect(ChartHistoryStore.pendingDraft(for: base.id)?.chart == draft && ChartHistoryStore.baseline(for: base.id) == nil, "legacy draft stays intact and requires explicit review")
    }

    static func testTierContentPayload() throws {
        // Tier charts ride the same CloudKit Chart record as grids; the kind tag
        // in ChartContent JSON is what tells the fetch path how to decode it.
        var tier = TierState.makeDefault()
        expect(tier.isValid, "default tier chart is valid")
        tier.title = "Fast food"
        var wendys = ChartCell()
        wendys.caption = "Wendy's"
        var shack = ChartCell()
        shack.caption = "Shake Shack"
        tier.tiers[0].items = [wendys, shack]
        var arbys = ChartCell()
        arbys.caption = "Arby's"
        tier.unranked = [arbys]
        let tierPayload = try JSONEncoder().encode(ChartContent.tier(tier))
        expect(String(decoding: tierPayload, as: UTF8.self).contains("\"kind\":\"tier\""), "tier payload carries the tier kind tag")
        let decoded = try JSONDecoder().decode(ChartContent.self, from: tierPayload)
        expect(decoded.kind == .tier, "decoded content keeps the tier kind")
        expect(decoded.hasSameContent(as: .tier(tier)), "tier chart survives the CloudKit payload round trip")
        let gridPayload = try JSONEncoder().encode(ChartContent.grid(ChartState()))
        expect(String(decoding: gridPayload, as: UTF8.self).contains("\"kind\":\"grid\""), "grid payload carries the grid kind tag")

        // TierState.isValid boundary checks the sync layer relies on.
        var twoTiers = TierState.makeDefault()
        twoTiers.setTierCount(2)
        expect(twoTiers.isValid, "two tiers is the minimum")
        var eightTiers = TierState.makeDefault()
        eightTiers.setTierCount(8)
        expect(eightTiers.isValid, "eight tiers is the maximum")
        var oneTier = TierState.makeDefault()
        oneTier.tiers = [oneTier.tiers[0]]
        expect(!oneTier.isValid, "one tier is below the minimum")
        var nineTiers = TierState.makeDefault()
        nineTiers.tiers += (0..<3).map { _ in Tier(label: "X", color: TierColor.defaultPalette[0], items: []) }
        expect(!nineTiers.isValid, "nine tiers is above the maximum")
        var dupTiers = TierState.makeDefault()
        dupTiers.tiers[1].id = dupTiers.tiers[0].id
        expect(!dupTiers.isValid, "duplicate tier ids are rejected")
        var fullTier = TierState.makeDefault()
        fullTier.tiers[0].items = (0..<TierState.maxItemsPerTier).map { _ in ChartCell() }
        expect(fullTier.isValid, "a tier at the item cap is valid")
        fullTier.tiers[0].items.append(ChartCell())
        expect(!fullTier.isValid, "a tier over the item cap is invalid")
        var fullUnranked = TierState.makeDefault()
        fullUnranked.unranked = (0..<TierState.maxUnrankedItems).map { _ in ChartCell() }
        expect(fullUnranked.isValid, "unranked at the cap is valid")
        fullUnranked.unranked.append(ChartCell())
        expect(!fullUnranked.isValid, "unranked over the cap is invalid")
        var dupItems = TierState.makeDefault()
        let dup = ChartCell()
        dupItems.tiers[0].items = [dup]
        dupItems.unranked = [dup]
        expect(!dupItems.isValid, "an item id in both a tier and unranked is rejected")
        var crowded = TierState.makeDefault()
        crowded.setTierCount(4)
        for i in 0..<4 { crowded.tiers[i].items = (0..<TierState.maxItemsPerTier).map { _ in ChartCell() } }
        crowded.unranked = (0..<4).map { _ in ChartCell() }
        expect(crowded.isValid, "exactly 100 total items is valid")
        crowded.unranked.append(ChartCell())
        expect(!crowded.isValid, "over 100 total items is invalid")

        // MARK: - TierMerge three-way merge

        func tierBase() -> TierState {
            var t = TierState.makeDefault()
            var a = ChartCell(); a.caption = "A"
            var b = ChartCell(); b.caption = "B"
            var c = ChartCell(); c.caption = "C"
            t.tiers[0].items = [a, b, c]
            var u = ChartCell(); u.caption = "U"
            t.unranked = [u]
            return t
        }

        // Disjoint moves and edits merge cleanly, each item exactly once.
        var tb = tierBase()
        var tm = tb
        var ts = tb
        let aID = tb.tiers[0].items[0].id
        let uID = tb.unranked[0].id
        tm.tiers[0].items.remove(at: 0)
        tm.tiers[1].items = [tb.tiers[0].items[0]]
        ts.tiers[0].items[1].caption = "B2"
        ts.unranked.removeAll()
        ts.tiers[2].items = [tb.unranked[0]]
        var tresult = TierMerge.merge(base: tb, local: tm, remote: ts)
        expect(tresult.conflicts.isEmpty, "disjoint tier moves and edits merge")
        let mergedIDs = tresult.tier.tiers.flatMap { $0.items.map(\.id) } + tresult.tier.unranked.map(\.id)
        expect(Set(mergedIDs).count == mergedIDs.count, "merged tier chart has no duplicate items")
        expect(tresult.tier.isValid, "merged tier chart is valid")
        expect(tresult.tier.tiers[1].items.map(\.id) == [aID], "local move survives")
        expect(tresult.tier.tiers[2].items.map(\.id) == [uID], "remote move survives")
        expect(tresult.tier.tiers[0].items.first(where: { $0.caption == "B2" }) != nil, "remote caption edit survives")

        // Same title on both sides conflicts; choices resolve.
        tb = tierBase(); tm = tb; ts = tb
        tm.title = "Mine"; ts.title = "Theirs"
        tresult = TierMerge.merge(base: tb, local: tm, remote: ts)
        expect(tresult.conflicts.map(\.id) == ["title"], "same title edit conflicts")
        tresult = TierMerge.merge(base: tb, local: tm, remote: ts, choices: ["title": .mine])
        expect(tresult.conflicts.isEmpty && tresult.tier.title == "Mine", "title choice applies")

        // Same item moved to different tiers conflicts; choices resolve.
        tb = tierBase(); tm = tb; ts = tb
        let movedID = tb.tiers[0].items[0].id
        tm.tiers[0].items.remove(at: 0); tm.tiers[1].items = [tb.tiers[0].items[0]]
        ts.tiers[0].items.remove(at: 0); ts.tiers[2].items = [tb.tiers[0].items[0]]
        tresult = TierMerge.merge(base: tb, local: tm, remote: ts)
        expect(tresult.conflicts.map(\.id) == ["item-\(movedID.uuidString)-moved"], "same item moved to two tiers conflicts")
        tresult = TierMerge.merge(base: tb, local: tm, remote: ts, choices: ["item-\(movedID.uuidString)-moved": .mine])
        expect(tresult.conflicts.isEmpty && tresult.tier.tiers[1].items.map(\.id) == [movedID], "move choice applies")

        // Delete versus edit conflicts; untouched delete wins silently.
        tb = tierBase(); tm = tb; ts = tb
        let delID = tb.tiers[0].items[0].id
        tm.tiers[0].items.remove(at: 0)
        ts.tiers[0].items[0].caption = "A2"
        tresult = TierMerge.merge(base: tb, local: tm, remote: ts)
        expect(tresult.conflicts.map(\.id) == ["item-removed-\(delID.uuidString)"], "delete versus edit conflicts")
        tresult = TierMerge.merge(base: tb, local: tm, remote: ts, choices: ["item-removed-\(delID.uuidString)": .shared])
        expect(tresult.conflicts.isEmpty, "delete conflict resolves")
        expect(tresult.tier.tiers[0].items.first(where: { $0.id == delID })?.caption == "A2", "kept side of delete conflict survives")
        tm = tb; ts = tb
        tm.tiers[0].items.remove(at: 0)
        tresult = TierMerge.merge(base: tb, local: tm, remote: ts)
        expect(tresult.conflicts.isEmpty, "uncontested delete merges silently")

        // Tier removed by one side spills its items to unranked, no conflict.
        tb = tierBase(); tm = tb; ts = tb
        tm.setTierCount(5)
        tresult = TierMerge.merge(base: tb, local: tm, remote: ts)
        expect(tresult.conflicts.isEmpty, "uncontested tier removal merges")
        expect(tresult.tier.tiers.count == 5, "removed tier is gone")
        expect(tresult.tier.isValid, "tier removal merge stays valid")

        // Tier removed by one side and relabeled by the other conflicts.
        tb = tierBase(); tm = tb; ts = tb
        let removedTierID = tb.tiers[5].id
        tm.setTierCount(5)
        ts.tiers[5].label = "Z"
        tresult = TierMerge.merge(base: tb, local: tm, remote: ts)
        expect(tresult.conflicts.map(\.id) == ["tier-removed-\(removedTierID.uuidString)"], "delete versus relabel tier conflicts")

        // Keeping a tier after delete-versus-relabel introduces no phantom
        // second conflict.
        let existenceKey = "tier-removed-\(removedTierID.uuidString)"
        tresult = TierMerge.merge(base: tb, local: tm, remote: ts, choices: [existenceKey: .shared])
        expect(tresult.conflicts.isEmpty, "keeping the tier resolves without a phantom label conflict")
        expect(tresult.tier.tiers.contains(where: { $0.id == removedTierID && $0.label == "Z" }), "kept tier keeps the remote label")

        // Independent label and color edits merge without a deletion conflict.
        tb = tierBase(); tm = tb; ts = tb
        tm.tiers[0].label = "Top"
        ts.tiers[0].color = TierColor.defaultPalette[1]
        tresult = TierMerge.merge(base: tb, local: tm, remote: ts)
        expect(tresult.conflicts.isEmpty, "independent label and color edits merge")
        expect(tresult.tier.tiers[0].label == "Top" && tresult.tier.tiers[0].color == TierColor.defaultPalette[1], "label and color edits both survive")

        // An item kept after delete-versus-edit stays ranked even when the
        // winning order sequence no longer contains it.
        tb = tierBase(); tm = tb; ts = tb
        let keepID = tb.tiers[0].items[0].id
        tm.tiers[0].items.remove(at: 0)
        tm.tiers[0].items.reverse()
        ts.tiers[0].items[0].caption = "A2"
        tresult = TierMerge.merge(base: tb, local: tm, remote: ts, choices: ["item-removed-\(keepID.uuidString)": .shared])
        expect(tresult.conflicts.isEmpty, "kept item resolution is complete")
        expect(tresult.tier.tiers[0].items.contains(where: { $0.id == keepID }), "item kept after delete-versus-edit stays ranked")
        expect(tresult.tier.isValid, "kept-item merge stays valid")

        // An item added into a tier the other side removed spills to unranked.
        tb = tierBase(); tm = tb; ts = tb
        tm.setTierCount(5)
        var addedX = ChartCell(); addedX.caption = "X"
        ts.tiers[5].items = [addedX]
        let spillKey = "tier-removed-\(tb.tiers[5].id.uuidString)"
        tresult = TierMerge.merge(base: tb, local: tm, remote: ts)
        expect(tresult.conflicts.map(\.id) == [spillKey], "add into removed tier conflicts")
        tresult = TierMerge.merge(base: tb, local: tm, remote: ts, choices: [spillKey: .mine])
        expect(tresult.conflicts.isEmpty, "tier removal choice resolves")
        expect(tresult.tier.unranked.contains(where: { $0.id == addedX.id }), "item added into a removed tier spills to unranked")
        expect(tresult.tier.isValid, "spill merge stays valid")

        // Capacity overflow goes to review instead of dead-ending the share.
        tb = tierBase()
        tb.unranked = (0..<30).map { _ in ChartCell() }
        tm = tb; ts = tb
        tm.unranked += (0..<18).map { _ in ChartCell() }
        ts.unranked += (0..<18).map { _ in ChartCell() }
        tresult = TierMerge.merge(base: tb, local: tm, remote: ts)
        expect(tresult.conflicts.map(\.id) == ["tier-capacity"], "unranked overflow goes to review")
        tresult = TierMerge.merge(base: tb, local: tm, remote: ts, choices: ["tier-capacity": .mine])
        expect(tresult.conflicts.isEmpty && tresult.tier.isValid, "capacity choice resolves to a valid chart")

        // Insertions that shift indices are not moves: no order conflict.
        tb = tierBase(); tm = tb; ts = tb
        var inserted = ChartCell(); inserted.caption = "New"
        tm.tiers[0].items.insert(inserted, at: 0)
        ts.tiers[0].items[2].caption = "C2"
        tresult = TierMerge.merge(base: tb, local: tm, remote: ts)
        expect(tresult.conflicts.isEmpty, "index shift from insertion does not conflict")
        expect(tresult.tier.tiers[0].items.map(\.caption) == ["New", "A", "B", "C2"], "insertion order and remote edit both survive")

        // Structural tier-count overflow goes to review, not truncation.
        tb = tierBase(); tm = tb; ts = tb
        tm.addTier(label: "G", color: TierColor.defaultPalette[0])
        tm.addTier(label: "H", color: TierColor.defaultPalette[1])
        ts.addTier(label: "I", color: TierColor.defaultPalette[2])
        tresult = TierMerge.merge(base: tb, local: tm, remote: ts)
        expect(tresult.conflicts.map(\.id) == ["tier-structure"], "nine tiers goes to review")
        tresult = TierMerge.merge(base: tb, local: tm, remote: ts, choices: ["tier-structure": .mine])
        expect(tresult.conflicts.isEmpty && tresult.tier.tiers.count == 8, "structural choice applies")

        // Older draft without a base needs an explicit whole-chart choice.
        tm = tierBase(); ts = tierBase()
        tm.title = "Old draft"; ts.title = "New draft"
        tresult = TierMerge.merge(base: nil, local: tm, remote: ts)
        expect(tresult.conflicts.map(\.id) == ["tierchart"], "baseless tier draft needs review")
        tresult = TierMerge.merge(base: nil, local: tm, remote: ts, choices: ["tierchart": .mine])
        expect(tresult.conflicts.isEmpty && tresult.tier.title == "Old draft", "baseless tier choice applies")
    }
}
