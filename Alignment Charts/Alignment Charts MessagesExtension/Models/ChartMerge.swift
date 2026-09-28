import Foundation

enum ChartConflictChoice: String, Sendable {
    case mine, shared
}

enum ChartConflictPreview: Sendable {
    case text(String)
    case image(UUID?)
    case chart(ChartState)
}

struct ChartConflict: Identifiable, Sendable {
    let id: String
    let title: String
    let mine: ChartConflictPreview
    let shared: ChartConflictPreview
}

struct ChartMergeResult: Sendable {
    var chart: ChartState
    var conflicts: [ChartConflict]
}

struct ChartMergeReview: Error, Identifiable, Sendable {
    let id = UUID()
    let base: ChartState?
    let local: ChartState
    let remote: ChartState

    func merged(choices: [String: ChartConflictChoice] = [:]) -> ChartMergeResult {
        ChartMerge.merge(base: base, local: local, remote: remote, choices: choices)
    }
}

/// Three-way content merge. Never use a freshly fetched chart as the user's baseline.
enum ChartMerge {
    private struct Grid: Equatable {
        var rowLabels: [String]
        var columnLabels: [String]
        var cells: [ChartCell]

        init(_ chart: ChartState) {
            rowLabels = chart.rowLabels
            columnLabels = chart.columnLabels
            cells = chart.cells
        }
    }

    static func merge(
        base: ChartState?, local: ChartState, remote: ChartState,
        choices: [String: ChartConflictChoice] = [:]
    ) -> ChartMergeResult {
        var conflicts: [ChartConflict] = []
        func choose<T: Equatable>(
            _ original: T, _ mine: T, _ shared: T, id: String, title: String,
            preview: (T) -> ChartConflictPreview
        ) -> T {
            if mine == shared { return mine }
            if mine == original { return shared }
            if shared == original { return mine }
            if let choice = choices[id] { return choice == .mine ? mine : shared }
            conflicts.append(ChartConflict(id: id, title: title, mine: preview(mine), shared: preview(shared)))
            return shared // A placeholder only: unresolved results must never be uploaded.
        }

        guard let base else {
            // Older drafts have no trustworthy ancestor. Require an explicit choice.
            if local.hasSameContent(as: remote) { return ChartMergeResult(chart: remote, conflicts: []) }
            if let choice = choices["chart"] {
                var selected = choice == .mine ? local : remote
                selected.daily = remote.daily
                return ChartMergeResult(chart: selected, conflicts: [])
            }
            return ChartMergeResult(chart: remote, conflicts: [ChartConflict(
                id: "chart", title: "This older draft needs review", mine: .chart(local), shared: .chart(remote)
            )])
        }

        var merged = remote
        merged.title = choose(base.title, local.title, remote.title, id: "title", title: "Chart title", preview: ChartConflictPreview.text)
        merged.rowAxisTitle = choose(base.rowAxisTitle, local.rowAxisTitle, remote.rowAxisTitle, id: "rowAxis", title: "Row title", preview: ChartConflictPreview.text)
        merged.columnAxisTitle = choose(base.columnAxisTitle, local.columnAxisTitle, remote.columnAxisTitle, id: "columnAxis", title: "Column title", preview: ChartConflictPreview.text)

        func sameLayout(_ a: ChartState, _ b: ChartState) -> Bool {
            a.rows == b.rows && a.columns == b.columns && a.cells.map(\.id) == b.cells.map(\.id)
        }
        func removesEdits(resized: ChartState, edited: ChartState) -> Bool {
            let retained = Set(resized.cells.map(\.id))
            let oldCells = Dictionary(uniqueKeysWithValues: base.cells.map { ($0.id, $0) })
            if edited.cells.contains(where: { !retained.contains($0.id) && oldCells[$0.id] != $0 }) { return true }
            for i in resized.rows..<max(resized.rows, base.rows) where edited.rowLabels.indices.contains(i) {
                if edited.rowLabels[i] != base.rowLabels[i] { return true }
            }
            for i in resized.columns..<max(resized.columns, base.columns) where edited.columnLabels.indices.contains(i) {
                if edited.columnLabels[i] != base.columnLabels[i] { return true }
            }
            return false
        }

        let localResized = !sameLayout(local, base)
        let remoteResized = !sameLayout(remote, base)
        let incompatible = (!sameLayout(local, remote) && localResized && remoteResized)
            || (localResized && removesEdits(resized: local, edited: remote))
            || (remoteResized && removesEdits(resized: remote, edited: local))

        if incompatible {
            let grid = choose(Grid(base), Grid(local), Grid(remote), id: "grid", title: "Layout and cell changes") { value in
                var preview = merged
                preview.rowLabels = value.rowLabels
                preview.columnLabels = value.columnLabels
                preview.cells = value.cells
                return .chart(preview)
            }
            merged.rowLabels = grid.rowLabels
            merged.columnLabels = grid.columnLabels
            merged.cells = grid.cells
        } else {
            let layout = localResized ? local : remote
            merged.rowLabels = layout.rowLabels
            merged.columnLabels = layout.columnLabels
            merged.cells = layout.cells
            for i in merged.rowLabels.indices {
                merged.rowLabels[i] = choose(
                    base.rowLabels[safe: i] ?? "", local.rowLabels[safe: i] ?? "", remote.rowLabels[safe: i] ?? "",
                    id: "row-\(i)", title: "Row \(i + 1) label", preview: ChartConflictPreview.text)
            }
            for i in merged.columnLabels.indices {
                merged.columnLabels[i] = choose(
                    base.columnLabels[safe: i] ?? "", local.columnLabels[safe: i] ?? "", remote.columnLabels[safe: i] ?? "",
                    id: "column-\(i)", title: "Column \(i + 1) label", preview: ChartConflictPreview.text)
            }
            let originals = Dictionary(uniqueKeysWithValues: base.cells.map { ($0.id, $0) })
            let mine = Dictionary(uniqueKeysWithValues: local.cells.map { ($0.id, $0) })
            let shared = Dictionary(uniqueKeysWithValues: remote.cells.map { ($0.id, $0) })
            for i in merged.cells.indices {
                let cell = merged.cells[i]
                guard let l = mine[cell.id], let r = shared[cell.id] else { continue }
                let b = originals[cell.id]
                let location = "Row \(i / merged.columns + 1), column \(i % merged.columns + 1)"
                merged.cells[i].caption = choose(b?.caption ?? "", l.caption, r.caption,
                    id: "\(cell.id)-caption", title: "\(location): text", preview: ChartConflictPreview.text)
                let image = choose(b?.imageReference, l.imageReference, r.imageReference,
                    id: "\(cell.id)-image", title: "\(location): photo", preview: ChartConflictPreview.image)
                // Keep legacy encoding unchanged unless the reference actually changes.
                if merged.cells[i].imageReference != image { merged.cells[i].setImageReference(image) }
            }
        }
        merged.updatedAt = max(local.updatedAt, remote.updatedAt)
        return ChartMergeResult(chart: merged, conflicts: conflicts)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
