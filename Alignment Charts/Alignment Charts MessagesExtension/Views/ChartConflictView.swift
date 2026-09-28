import SwiftUI

struct ChartConflictView: View {
    let review: ChartMergeReview
    let onResolve: ([String: ChartConflictChoice]) -> Void
    let onCancel: () -> Void
    @State private var choices: [String: ChartConflictChoice] = [:]

    private var conflicts: [ChartConflict] { review.merged().conflicts }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Someone else edited this chart too. Changes that fit together are combined automatically. Choose which version to keep for each conflict below.")
                    if conflicts.contains(where: { $0.id == "grid" }) {
                        Text("A layout change overlaps other edits. Choosing a grid keeps its layout, labels, and cells. Review both grids carefully.")
                    }
                    if conflicts.contains(where: { $0.id == "chart" }) {
                        Text("This draft was saved before change tracking was available. Choose the whole chart to keep.")
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
            }
        }
        .padding(.vertical, 6)
    }
}
