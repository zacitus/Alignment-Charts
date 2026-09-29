import SwiftUI

/// Render-only view for tier charts. Never interactive — consumed exclusively
/// by ``TierImageRenderer`` to produce the flat bubble / Photos image.
struct TierChartView: View {
    let tier: TierState

    private let chipSize: CGFloat = 64
    private let labelColumnWidth: CGFloat = 96

    var body: some View {
        VStack(spacing: 10) {
            if !tier.title.isEmpty {
                Text(tier.title)
                    .font(.title2.bold())
                    .foregroundStyle(.black)
            }
            ForEach(tier.tiers) { row in
                tierRow(row)
            }
            if !tier.unranked.isEmpty {
                unrankedTray
            }
        }
    }

    private func tierRow(_ row: Tier) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(row.label.isEmpty ? "Tier" : row.label)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: labelColumnWidth, alignment: .center).frame(minHeight: chipSize, alignment: .center)
                .background(row.color.swiftUIColor())
            chipGrid(row.items)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color.white)
        .overlay(Rectangle().stroke(Color.black.opacity(0.2), lineWidth: 1))
    }

    private var unrankedTray: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Unranked")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            chipGrid(tier.unranked)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.18))
        .cornerRadius(8)
        .opacity(0.75)
    }

    private func chipGrid(_ items: [ChartCell]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(items) { item in
                // ChartCellContent already falls back to a caption/plus glyph when the
                // image is missing, so a chip is never blank in the render.
                ChartCellContent(cell: item)
                    .frame(width: chipSize, height: chipSize)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
        }
        // Keep empty tiers visible as a labeled row rather than collapsing away.
        .frame(minHeight: chipSize, alignment: .top)
    }
}

/// Eager wrapping layout for the render path. `ImageRenderer` does not reliably
/// render lazy containers (`LazyVGrid` etc.) — exports can come out clipped to an
/// initial frame — so the share-image layout uses this non-lazy flow instead.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGSize {
        layout(width: proposal.width ?? 0, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let laidOut = layout(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: laidOut.origins[index], anchor: .topLeading, proposal: .unspecified)
        }
    }

    private func layout(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        origins.reserveCapacity(subviews.count)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widestRow: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            // Unspecified width: single row. Otherwise wrap when the chip overflows.
            if width > 0, x > 0, x + size.width > width {
                widestRow = max(widestRow, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        widestRow = max(widestRow, x > 0 ? x - spacing : 0)
        return (CGSize(width: widestRow, height: y + rowHeight), origins)
    }
}
