import SwiftUI

struct TierThumbnailView: View {
    let tier: TierState

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(tier.tiers.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 6) {
                    Text(row.label.isEmpty ? "Tier \(index + 1)" : row.label)
                        .font(.system(size: 8, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.black)
                        .frame(width: 40)
                        .frame(maxHeight: .infinity)
                        .background(row.color.swiftUIColor())
                    ForEach(0..<min(row.items.count, 8), id: \.self) { _ in
                        Circle().fill(.gray).frame(width: 6, height: 6)
                    }
                    if row.items.count > 8 {
                        Text("\(row.items.count)")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                .background(Color(uiColor: .secondarySystemBackground))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .environment(\.colorScheme, .light)
        .accessibilityHidden(true)
    }
}

struct TierBadge: View {
    var body: some View {
        Text("TIER")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
    }
}
