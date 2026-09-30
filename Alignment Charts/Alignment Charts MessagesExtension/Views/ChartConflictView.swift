import SwiftUI

struct ChartConflictView: View {
    let review: PendingMergeReview
    let onResolve: ([String: ChartConflictChoice]) -> Void
    let onCancel: () -> Void
    @State private var choices: [String: ChartConflictChoice] = [:]

    private var conflicts: [ChartConflict] { review.conflicts }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Someone else edited this chart too. Changes that fit together are combined automatically. Choose which version to keep for each conflict below.")
                    if conflicts.contains(where: { $0.id == "grid" }) {
                        Text("A layout change overlaps other edits. Choosing a grid keeps its layout, labels, and cells. Review both grids carefully.")
                    }
                    if conflicts.contains(where: { $0.id == "chart" || $0.id == "tierchart" }) {
                        Text("This draft was saved before change tracking was available. Choose the whole chart to keep.")
                    }
                    if conflicts.contains(where: { $0.id == "tier-structure" }) {
                        Text("Both sides added tiers and the chart no longer fits the 2 to 8 tier limit. Choose the whole chart to keep, then re-add the missing tiers.")
                    }
                    if conflicts.contains(where: { $0.id == "tier-capacity" }) {
                        Text("Both sides added items and the chart no longer fits the item limits. Choose the whole chart to keep, then re-add the missing items.")
                    }
                }
                ForEach(conflicts) { conflict in
                    Section(conflict.title) {
                        alternative("My version", preview: conflict.mine, choice: .mine, conflict: conflict)
                        alternative("Shared version", preview: conflict.shared, choice: .shared, conflict: conflict)
                    }
                }
            }
            .navigationTitle("Review changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") { onResolve(choices) }
                        .disabled(conflicts.contains { choices[$0.id] == nil })
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func alternative(
        _ title: String, preview: ChartConflictPreview,
        choice: ChartConflictChoice, conflict: ChartConflict
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                choices[conflict.id] = choice
            } label: {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Image(systemName: choices[conflict.id] == choice ? "checkmark.circle.fill" : "circle")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(choices[conflict.id] == choice ? Color.blue : Color.primary)
            .accessibilityAddTraits(choices[conflict.id] == choice ? .isSelected : [])
            switch preview {
            case .text(let text):
                Text(text.isEmpty ? "(Empty)" : text)
                    .foregroundStyle(.secondary)
            case .image(let id):
                if let id, let image = ImageStore.image(for: id) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200)
                } else {
                    Text(id == nil ? "No photo" : "Photo unavailable").foregroundStyle(.secondary)
                }
            case .chart(let chart):
                ScrollView(.horizontal) {
                    ChartGridView(chart: chart).padding(8).background(.white)
                        .environment(\.colorScheme, .light)
                }
            case .tier(let tier):
                ScrollView(.horizontal) {
                    TierConflictPreview(tier: tier).padding(8).background(.white)
                        .environment(\.colorScheme, .light)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

/// Readable tier-chart preview for conflict review: tier labels in their
/// colors plus item captions, with Unranked included. The thumbnail's dots
/// hide exactly the information a merge choice needs.
private struct TierConflictPreview: View {
    let tier: TierState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tier.title.isEmpty {
                Text(tier.title).font(.headline)
            }
            ForEach(tier.tiers) { t in
                HStack(alignment: .top, spacing: 8) {
                    Text(t.label.isEmpty ? "·" : t.label)
                        .font(.caption).bold()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(t.color.swiftUIColor())
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(itemSummary(t.items))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: 220, alignment: .leading)
                }
            }
            if !tier.unranked.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text("Unranked")
                        .font(.caption).bold()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(uiColor: .systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(itemSummary(tier.unranked))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: 220, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 280, alignment: .leading)
    }

    private func itemSummary(_ items: [ChartCell]) -> String {
        guard !items.isEmpty else { return "(empty)" }
        let captions = items.map { $0.caption.isEmpty ? "(untitled)" : $0.caption }
        let shown = captions.prefix(8).joined(separator: ", ")
        return items.count > 8 ? "\(shown), +\(items.count - 8) more" : shown
    }
}
