import SwiftUI
import UniformTypeIdentifiers

struct UnrankedTrayView: View {
    let unranked: [ChartCell]
    let onTap: (UUID) -> Void
    let onAdd: () -> Void
    let onMoveToUnranked: (UUID) -> Bool
    var allTiers: [(id: UUID, label: String)] = []
    var onMoveToTier: (UUID, UUID) -> Bool = { _, _ in false }
    var onReorder: ((UUID, Int) -> Void)? = nil

    @State private var isDropTarget = false
    @State private var insertionIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Unranked").font(.headline)
                Spacer()
                Button(action: onAdd) { Image(systemName: "plus") }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Add item to Unranked")
            }
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 0) {
                    if unranked.isEmpty {
                        Text("Items waiting to be ranked")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 76)
                    }
                    ForEach(unranked) { cell in
                        Button { onTap(cell.id) } label: {
                            ChartCellContent(cell: cell)
                                .frame(width: 76, height: 76)
                                .background(Color(uiColor: .systemBackground))
                                .overlay(Rectangle().stroke(Color.secondary.opacity(0.25)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(cell.caption.isEmpty ? "Unnamed item" : cell.caption)
                        .onDrag { NSItemProvider(object: cell.id.uuidString as NSString) }
                        .contextMenu { moveActions(for: cell.id) }
                        .accessibilityActions { moveActions(for: cell.id) }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDropTarget ? Color.blue : Color.clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onDrop(of: [UTType.text], delegate: TierDropDelegate(
            highlighted: $isDropTarget,
            insertionIndex: $insertionIndex,
            itemCount: unranked.count,
            estimatesIndex: false,
            onMove: { cellID, _ in onMoveToUnranked(cellID) }
        ))
    }

    private func moveActions(for cellID: UUID) -> some View {
        TierItemMoveActions(
            allTiers: allTiers,
            onMove: { destination in
                if destination == TierMoveDestination.unranked.id {
                    _ = onMoveToUnranked(cellID)
                } else {
                    _ = onMoveToTier(cellID, destination)
                }
            },
            onReorder: onReorder.map { reorder in { direction in reorder(cellID, direction) } }
        )
    }
}
