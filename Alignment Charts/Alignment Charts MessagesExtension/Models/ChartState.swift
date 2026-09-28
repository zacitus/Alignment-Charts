import Foundation

struct ChartState: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String = ""
    var rowAxisTitle: String = ""
    var columnAxisTitle: String = ""
    var rowLabels: [String]
    var columnLabels: [String]
    var cells: [ChartCell]
    var updatedAt: Date = .now
    var daily: DailyIdentity? = nil

    /// Timestamps describe activity, not whether the user changed chart content.
    func hasSameContent(as other: ChartState) -> Bool {
        var lhs = self
        var rhs = other
        lhs.updatedAt = .distantPast
        rhs.updatedAt = .distantPast
        return lhs == rhs
    }

    var isValid: Bool {
        Self.sizeRange.contains(rows) && Self.sizeRange.contains(columns)
            && cells.count == rows * columns && Set(cells.map(\.id)).count == cells.count
    }

    static let sizeRange = 2...6

    init(rows: Int = 3, columns: Int = 3) {
        rowLabels = Array(repeating: "", count: rows)
        columnLabels = Array(repeating: "", count: columns)
        cells = (0..<(rows * columns)).map { _ in ChartCell() }
    }

    var rows: Int { rowLabels.count }
    var columns: Int { columnLabels.count }

    var filledCellCount: Int {
        cells.filter { $0.hasImage || !$0.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var isComplete: Bool { !cells.isEmpty && filledCellCount == cells.count }

    func cellIndex(row: Int, column: Int) -> Int { row * columns + column }

    mutating func setRows(_ newRows: Int) {
        let target = min(max(newRows, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        guard target != rows else { return }
        var newCells: [ChartCell] = []
        for r in 0..<target {
            for c in 0..<columns {
                newCells.append(r < rows ? cells[cellIndex(row: r, column: c)] : ChartCell())
            }
        }
        rowLabels = Self.resize(rowLabels, to: target)
        cells = newCells
    }

    mutating func setColumns(_ newColumns: Int) {
        let target = min(max(newColumns, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        guard target != columns else { return }
        var newCells: [ChartCell] = []
        for r in 0..<rows {
            for c in 0..<target {
                newCells.append(c < columns ? cells[cellIndex(row: r, column: c)] : ChartCell())
            }
        }
        columnLabels = Self.resize(columnLabels, to: target)
        cells = newCells
    }

    private static func resize(_ labels: [String], to count: Int) -> [String] {
        if labels.count >= count { return Array(labels.prefix(count)) }
        return labels + Array(repeating: "", count: count - labels.count)
    }
}
