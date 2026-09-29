import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct TierRowView: View {
    let tier: Tier
    let tierIndex: Int
    let onTap: (UUID) -> Void
    let onMove: (UUID, Int, Int?) -> Bool
    let highlighted: Bool
    let allTiers: [(id: UUID, label: String)]
    let onMoveToTier: (UUID, UUID) -> Bool
    let onReorderWithinTier: (UUID, Int) -> Void

    @State private var isDropTarget = false
    @State private var insertionIndex: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var label: String {
        tier.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Tier \(tierIndex + 1)" : tier.label
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.black)
                .frame(width: 64, height: 76)
                .background(tier.color.swiftUIColor())
                .onDrop(of: [UTType.text], delegate: dropDelegate(estimatesIndex: false))

            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 0) {
                        ForEach(tier.items) { cell in
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
                    .frame(minWidth: geometry.size.width, minHeight: 76, alignment: .leading)
                    .contentShape(Rectangle())
                    .overlay(alignment: .leading) {
                        if isDropTarget, let insertionIndex {
                            Rectangle()
                                .fill(.blue)
                                .frame(width: 3, height: 76)
                                .offset(x: CGFloat(insertionIndex) * 76)
                                .allowsHitTesting(false)
                        }
                    }
                    // The delegate's coordinates belong to the scrolling content, not the viewport.
                    .onDrop(of: [UTType.text], delegate: dropDelegate(estimatesIndex: true))
                }
            }
            .frame(height: 76)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay {
            Rectangle()
                .stroke(highlighted || isDropTarget ? Color.blue : Color.clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .animation(reduceMotion || UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.15), value: isDropTarget)
    }

    private func moveActions(for cellID: UUID) -> some View {
        TierItemMoveActions(
            allTiers: allTiers,
            onMove: { _ = onMoveToTier(cellID, $0) },
            onReorder: { onReorderWithinTier(cellID, $0) }
        )
    }

    private func dropDelegate(estimatesIndex: Bool) -> TierDropDelegate {
        TierDropDelegate(
            highlighted: $isDropTarget,
            insertionIndex: $insertionIndex,
            itemCount: tier.items.count,
            estimatesIndex: estimatesIndex,
            onMove: { onMove($0, tierIndex, $1) }
        )
    }
}

/// The same buttons supply context-menu commands and VoiceOver custom actions.
struct TierItemMoveActions: View {
    let allTiers: [(id: UUID, label: String)]
    let onMove: (UUID) -> Void
    var onReorder: ((Int) -> Void)? = nil

    var body: some View {
        ForEach(allTiers, id: \.id) { destination in
            Button("Move to \(destination.label)") { onMove(destination.id) }
        }
        Button("Move to Unranked") { onMove(TierMoveDestination.unranked.id) }
        if let onReorder {
            Button("Move left") { onReorder(-1) }
            Button("Move right") { onReorder(1) }
        }
    }
}

struct TierDropDelegate: DropDelegate {
    @Binding var highlighted: Bool
    @Binding var insertionIndex: Int?
    let itemCount: Int
    var estimatesIndex = true
    let onMove: (UUID, Int?) -> Bool

    func dropEntered(info: DropInfo) {
        highlighted = true
        insertionIndex = index(at: info.location)
    }

    func dropExited(info: DropInfo) {
        highlighted = false
        insertionIndex = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        insertionIndex = index(at: info.location)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        // DropInfo is only valid during this call. Capture the insertion point now.
        let destinationIndex = index(at: info.location)
        highlighted = false
        insertionIndex = nil
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, error in
            guard error == nil, let string = object as? NSString,
                  let cellID = UUID(uuidString: (string as String).trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            DispatchQueue.main.async {
                _ = onMove(cellID, destinationIndex)
            }
        }
        return true
    }

    private func index(at location: CGPoint) -> Int? {
        guard estimatesIndex, location.x.isFinite else { return nil }
        // Clamp before conversion to Int, including for providers outside our own app.
        return Int(min(max(location.x / 76, 0), CGFloat(itemCount)))
    }
}
