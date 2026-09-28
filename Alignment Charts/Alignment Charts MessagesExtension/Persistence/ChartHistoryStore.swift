import Foundation

/// Local per-device history of charts (drafts, sent, and received), one JSON file per chart.
///
/// Conversation scopes stay in this local wrapper rather than `ChartState` so participant
/// information is never included in the CloudKit payload for a shared chart.
enum ChartHistoryStore {
    private struct StoredChart: Codable {
        var chart: ChartState
        var base: ChartState?
        var conversationScopes: Set<String>
        var hiddenConversationScopes: Set<String>?

        /// A decoded file is only safe to hand to the carousel if its dimensions
        /// are internally consistent: `cellIndex(row:column:)` performs no bounds
        /// check, so a mismatch between `cells.count` and `rows * columns` can
        /// crash on every launch.
        var isConsistent: Bool {
            let rows = chart.rowLabels.count
            let columns = chart.columnLabels.count
            return rows > 0 && columns > 0
                && !chart.rowLabels.isEmpty && !chart.columnLabels.isEmpty
                && chart.cells.count == rows * columns
        }
    }

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Charts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + ".json")
    }

    /// Quarantine for files that can never be returned to the carousel.
    private static var corruptedDirectory: URL {
        let dir = directory.appendingPathComponent("Corrupted", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func quarantine(_ file: URL) {
        let destination = corruptedDirectory.appendingPathComponent(file.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try? FileManager.default.moveItem(at: file, to: destination)
    }

    /// Returns `false` when JSON encoding or the atomic write fails, so callers
    /// can surface silent draft loss instead of dropping changes unnoticed.
    @discardableResult
    static func save(_ chart: ChartState, base: ChartState?, in conversationScope: String) -> Bool {
        var scopes: Set<String> = []
        var hiddenScopes: Set<String> = []
        if let existingData = try? Data(contentsOf: url(for: chart.id)),
           let existing = try? JSONDecoder().decode(StoredChart.self, from: existingData) {
            scopes = existing.conversationScopes
            hiddenScopes = existing.hiddenConversationScopes ?? []
        }
        scopes.insert(conversationScope)

        let storedChart = StoredChart(
            chart: chart,
            base: base,
            conversationScopes: scopes,
            hiddenConversationScopes: hiddenScopes
        )
        do {
            let data = try JSONEncoder().encode(storedChart)
            try data.write(to: url(for: chart.id), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func savedVersion(for id: UUID) -> (chart: ChartState, base: ChartState?)? {
        guard let saved = stored(id) else { return nil }
        return (saved.chart, saved.base)
    }

    static func baseline(for id: UUID) -> ChartState? {
        stored(id)?.base
    }

    static func pendingDraft(for id: UUID) -> (chart: ChartState, base: ChartState?)? {
        guard let saved = stored(id), saved.base.map({ !saved.chart.hasSameContent(as: $0) }) ?? true else { return nil }
        return (saved.chart, saved.base)
    }

    /// Incoming messages must never replace an unsent local draft or its ancestor.
    static func receive(_ chart: ChartState, in scope: String) {
        if let draft = pendingDraft(for: chart.id) {
            save(draft.chart, base: draft.base, in: scope)
        } else {
            save(chart, base: chart, in: scope)
        }
    }

    private static func stored(_ id: UUID) -> StoredChart? {
        guard let data = try? Data(contentsOf: url(for: id)),
              let decoded = try? JSONDecoder().decode(StoredChart.self, from: data) else { return nil }
        // Same guard as the carousel path: never hand an internally
        // inconsistent chart to the editor or merge logic.
        guard decoded.isConsistent else {
            quarantine(url(for: id))
            return nil
        }
        return decoded
    }

    static func all(in conversationScope: String) -> [ChartState] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let charts = files.compactMap { file -> ChartState? in
            guard file.pathExtension == "json" else { return nil }
            guard let data = try? Data(contentsOf: file) else { return nil }
            guard let storedChart = try? JSONDecoder().decode(StoredChart.self, from: data),
                  storedChart.isConsistent else {
                // Move unreadable or internally inconsistent files out of the
                // store quietly, so they can never crash the carousel again.
                quarantine(file)
                return nil
            }
            guard storedChart.conversationScopes.contains(conversationScope),
                  !(storedChart.hiddenConversationScopes?.contains(conversationScope) ?? false) else { return nil }
            return storedChart.chart
        }
        return charts.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    static func hide(_ id: UUID, in conversationScope: String) {
        updateHiddenState(for: id, in: conversationScope, isHidden: true)
    }

    static func unhide(_ id: UUID, in conversationScope: String) {
        updateHiddenState(for: id, in: conversationScope, isHidden: false)
    }

    private static func updateHiddenState(for id: UUID, in conversationScope: String, isHidden: Bool) {
        guard let data = try? Data(contentsOf: url(for: id)),
              var storedChart = try? JSONDecoder().decode(StoredChart.self, from: data) else { return }

        var hiddenScopes = storedChart.hiddenConversationScopes ?? []
        if isHidden {
            hiddenScopes.insert(conversationScope)
        } else {
            hiddenScopes.remove(conversationScope)
        }
        storedChart.hiddenConversationScopes = hiddenScopes

        guard let updatedData = try? JSONEncoder().encode(storedChart) else { return }
        try? updatedData.write(to: url(for: id), options: .atomic)
    }
}
