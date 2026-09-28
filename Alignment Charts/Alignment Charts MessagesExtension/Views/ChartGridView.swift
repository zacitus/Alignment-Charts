import SwiftUI

struct ChartGridView: View {
    let chart: ChartState

    private var cellWidth: CGFloat { chart.columns > 4 ? 74 : 92 }
    private let cellHeight: CGFloat = 88
    private let rowLabelWidth: CGFloat = 88

    var body: some View {
        VStack(spacing: 10) {
            if !chart.title.isEmpty {
                Text(chart.title)
                    .font(.title2.bold())
                    .foregroundStyle(.black)
            }
            if !chart.columnAxisTitle.isEmpty {
                Text(chart.columnAxisTitle)
                    .font(.caption.bold())
                    .foregroundStyle(.black)
            }
            HStack(alignment: .center, spacing: 6) {
                if !chart.rowAxisTitle.isEmpty {
                    Text(chart.rowAxisTitle)
                        .font(.caption.bold())
                        .foregroundStyle(.black)
                        .rotationEffect(.degrees(-90))
                        .fixedSize()
                        .frame(width: 18)
                }
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        Color.clear.frame(width: rowLabelWidth, height: 44)
                        ForEach(Array(chart.columnLabels.enumerated()), id: \.offset) { _, label in
                            Text(label.isEmpty ? "Column" : label)
                                .font(.caption.bold())
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.black)
                                .frame(width: cellWidth, height: 44)
                        }
                    }
                    ForEach(0..<chart.rows, id: \.self) { row in
                        GridRow {
                            Text(chart.rowLabels[row].isEmpty ? "Row" : chart.rowLabels[row])
                                .font(.caption.bold())
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.black)
                                .frame(width: rowLabelWidth, height: cellHeight)
                            ForEach(0..<chart.columns, id: \.self) { column in
                                let cell = chart.cells[chart.cellIndex(row: row, column: column)]
                                ChartCellContent(cell: cell)
                                    .frame(width: cellWidth, height: cellHeight)
                                    .background(Color.white)
                                    .overlay(Rectangle().stroke(.black, lineWidth: 1))
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ChartCellContent: View {
    let cell: ChartCell
    var showsAddLabel = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                if cell.hasImage, let image = ImageStore.image(for: cell.imageStorageID) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else if cell.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if showsAddLabel {
                        Label("Add", systemImage: "plus")
                            .font(.body)
                            .foregroundStyle(.blue)
                    } else {
                        Image(systemName: "plus")
                            .foregroundStyle(.secondary)
                    }
                }
                if !cell.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(cell.caption)
                        .font(.caption2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .foregroundStyle(cell.hasImage ? Color.white : Color.primary)
                        .padding(4)
                        .frame(maxWidth: .infinity)
                        .background(cell.hasImage ? Color.black.opacity(0.68) : Color.clear)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipped()
        .contentShape(Rectangle())
    }
}
