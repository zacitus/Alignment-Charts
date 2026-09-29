import SwiftUI
import UIKit

struct TierEditorView: View {
    @Binding var tier: TierState
    let isNewChart: Bool
    let isSending: Bool
    let onClose: () -> Void
    let onShare: () -> Void

    @State private var selectedCell: TierCellSelection?
    @State private var isSaveFeedbackActive = false
    @State private var isTiersExpanded: Bool
    @State private var tierToDelete: UUID?
    @State private var showsDeleteConfirmation = false
    @State private var inlineNote: TierInlineNote?
    @State private var showsAISheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        tier: Binding<TierState>,
        isNewChart: Bool,
        isSending: Bool,
        onClose: @escaping () -> Void,
        onShare: @escaping () -> Void
    ) {
        _tier = tier
        self.isNewChart = isNewChart
        self.isSending = isSending
        self.onClose = onClose
        self.onShare = onShare
        _isTiersExpanded = State(initialValue: isNewChart)
    }

    private var rowAnimation: Animation? {
        reduceMotion || UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.2)
    }

    private var allTiers: [(id: UUID, label: String)] {
        tier.tiers.enumerated().map { index, row in
            (id: row.id, label: displayLabel(row, index: index))
        }
    }

    private var itemIDs: [UUID] {
        tier.tiers.flatMap { $0.items.map(\.id) } + tier.unranked.map(\.id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TextField("Untitled chart", text: $tier.title)
                        .font(.largeTitle.bold())
                        .textFieldStyle(.plain)
                        .padding(.top, 12)
                    tiersSection.padding(.top, 16)
                    chartSection.padding(.top, 26)
                    UnrankedTrayView(
                        unranked: tier.unranked,
                        onTap: selectCell,
                        onAdd: addItem,
                        onMoveToUnranked: { moveItem($0, to: TierMoveDestination.unranked.id) },
                        allTiers: allTiers,
                        onMoveToTier: { moveItem($0, to: $1) },
                        onReorder: reorderItem,
                        aiSuggestionsAvailable: AISuggestionsService.isAvailable,
                        onAIRequest: {
                            guard !isSending else { return }
                            showsAISheet = true
                        }
                    )
                    .sheet(isPresented: $showsAISheet) {
                        AISuggestionsSheet(onGenerate: addGeneratedSuggestions)
                    }
                    .padding(.top, 16)
                    if let inlineNote {
                        Text(inlineNote.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                    Text("Long-press to drag, tap to edit.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                }
                .padding()
            }
            .disabled(isSending)
            .background(Color(uiColor: .systemBackground))
            .foregroundStyle(Color(uiColor: .label))
            .tint(Color(uiColor: .label))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                        .disabled(isSending)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onShare) {
                        if isSending {
                            ProgressView()
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.message.fill")
                                Text(isNewChart ? "Add to iMessage" : "Update")
                            }
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(isSending)
                }
            }
            .sheet(item: $selectedCell) { selection in
                if let binding = cellBinding(for: selection.id) {
                    CellEditorView(
                        cell: binding,
                        moveDestinations: destinations(for: selection.id),
                        onMoveToTier: { destination in
                            let moved = moveItem(selection.id, to: destination)
                            if moved { selectedCell = nil }
                        }
                    )
                    .disabled(isSending)
                    .overlay(alignment: .bottom) {
                        if let inlineNote {
                            Text(inlineNote.message)
                                .font(.subheadline)
                                .padding(12)
                                .background(.regularMaterial, in: Capsule())
                                .padding()
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .onChange(of: itemIDs) { _, ids in
                if let selectedCell, !ids.contains(selectedCell.id) {
                    self.selectedCell = nil
                }
            }
            .confirmationDialog(deleteConfirmationTitle, isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("Move items and delete tier", role: .destructive) {
                    if let tierToDelete { deleteTier(tierToDelete) }
                    tierToDelete = nil
                }
                Button("Cancel", role: .cancel) { tierToDelete = nil }
            }
            .task(id: inlineNote?.id) {
                guard let noteID = inlineNote?.id else { return }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                if inlineNote?.id == noteID { inlineNote = nil }
            }
        }
    }

    private var tiersSection: some View {
        DisclosureGroup("Tiers", isExpanded: $isTiersExpanded) {
            VStack(spacing: 8) {
                ForEach(Array(tier.tiers.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 4) {
                        TextField("Tier \(index + 1)", text: labelBinding(for: row))
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                        ColorPicker("Color for \(displayLabel(row, index: index))", selection: colorBinding(for: row), supportsOpacity: false)
                            .labelsHidden()
                            .frame(minWidth: 44, minHeight: 44)
                        Button { reorderTier(row.id, direction: -1) } label: {
                            Image(systemName: "arrow.up")
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(index == 0)
                        .accessibilityLabel("Move \(displayLabel(row, index: index)) up")
                        Button { reorderTier(row.id, direction: 1) } label: {
                            Image(systemName: "arrow.down")
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(index == tier.tiers.count - 1)
                        .accessibilityLabel("Move \(displayLabel(row, index: index)) down")
                        Button(role: .destructive) { requestDelete(row) } label: {
                            Image(systemName: "trash")
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(tier.tiers.count <= TierState.tierCountRange.lowerBound)
                        .accessibilityLabel("Delete tier \(displayLabel(row, index: index))")
                    }
                }
                Button(action: addTier) { Label("Add tier", systemImage: "plus") }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .disabled(tier.tiers.count >= TierState.tierCountRange.upperBound)
            }
            .padding(.top, 16)
        }
        .font(.headline)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chart").font(.headline)
                    Text("Tap any item to add text and/or a photo.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 52)
                .opacity(isSaveFeedbackActive ? 0 : 1)
                .animation(rowAnimation, value: isSaveFeedbackActive)
                ChartSaveButton(content: .tier(tier), onActivityChange: { isSaveFeedbackActive = $0 })
                    .font(.title2)
            }
            VStack(spacing: 4) {
                ForEach(Array(tier.tiers.enumerated()), id: \.element.id) { index, row in
                    TierRowView(
                        tier: row,
                        tierIndex: index,
                        onTap: selectCell,
                        // Capture destination identity: loading a drag can outlive a row reorder.
                        onMove: { cellID, _, insertion in moveItem(cellID, to: row.id, at: insertion) },
                        highlighted: false,
                        allTiers: allTiers,
                        onMoveToTier: { moveItem($0, to: $1) },
                        onReorderWithinTier: reorderItem
                    )
                }
            }
            .padding(.top, 14)
        }
    }

    private func displayLabel(_ row: Tier, index: Int) -> String {
        row.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Tier \(index + 1)" : row.label
    }

    private func labelBinding(for row: Tier) -> Binding<String> {
        Binding(
            get: { tier.tiers.first(where: { $0.id == row.id })?.label ?? row.label },
            set: { value in
                guard !isSending, tier.tiers.contains(where: { $0.id == row.id }) else { return }
                tier.renameTier(id: row.id, label: value)
            }
        )
    }

    private func colorBinding(for row: Tier) -> Binding<Color> {
        Binding(
            get: { (tier.tiers.first(where: { $0.id == row.id })?.color ?? row.color).swiftUIColor() },
            set: { color in
                guard !isSending, tier.tiers.contains(where: { $0.id == row.id }),
                      let supported = closestPaletteColor(to: color) else { return }
                tier.setTierColor(id: row.id, color: supported)
            }
        )
    }

    // TierColor's shared interface exposes a palette, not arbitrary RGB construction.
    private func closestPaletteColor(to color: Color) -> TierColor? {
        func components(_ color: Color) -> (CGFloat, CGFloat, CGFloat) {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return (red, green, blue)
        }
        let target = components(color)
        func distance(_ candidate: TierColor) -> CGFloat {
            let value = components(candidate.swiftUIColor())
            let r = value.0 - target.0
            let g = value.1 - target.1
            let b = value.2 - target.2
            return r * r + g * g + b * b
        }
        return TierColor.defaultPalette.min { distance($0) < distance($1) }
    }

    private func addTier() {
        guard !isSending, tier.tiers.count < TierState.tierCountRange.upperBound,
              !TierColor.defaultPalette.isEmpty else { return }
        let color = TierColor.defaultPalette[tier.tiers.count % TierColor.defaultPalette.count]
        withAnimation(rowAnimation) {
            _ = tier.addTier(label: "", color: color)
        }
    }

    private func reorderTier(_ id: UUID, direction: Int) {
        guard !isSending, let index = tier.tiers.firstIndex(where: { $0.id == id }),
              tier.tiers.indices.contains(index + direction) else { return }
        withAnimation(rowAnimation) {
            tier.moveTier(from: index, to: index + direction)
        }
    }

    private func requestDelete(_ row: Tier) {
        guard !isSending, tier.tiers.count > TierState.tierCountRange.lowerBound else { return }
        if row.items.isEmpty {
            deleteTier(row.id)
        } else {
            tierToDelete = row.id
            showsDeleteConfirmation = true
        }
    }

    private var deleteConfirmationTitle: String {
        guard let id = tierToDelete, let index = tier.tiers.firstIndex(where: { $0.id == id }) else { return "Delete tier?" }
        let row = tier.tiers[index]
        return "Move \(row.items.count) items to Unranked and delete tier \(displayLabel(row, index: index))?"
    }

    private func deleteTier(_ id: UUID) {
        guard !isSending, tier.tiers.count > TierState.tierCountRange.lowerBound,
              let row = tier.tiers.first(where: { $0.id == id }) else { return }
        guard tier.unranked.count + row.items.count <= TierState.maxUnrankedItems else {
            showNote("Unranked is full")
            return
        }
        let removed = withAnimation(rowAnimation) { tier.removeTier(id: id) }
        if !removed { showNote("Couldn’t delete this tier") }
    }

    private func addItem() {
        guard !isSending else { return }
        guard tier.unranked.count < TierState.maxUnrankedItems else {
            showNote("Unranked is full")
            return
        }
        let cell = ChartCell()
        tier.unranked.append(cell)
        selectedCell = TierCellSelection(id: cell.id)
    }

    private func addGeneratedSuggestions(_ suggestions: [String]) {
        guard !isSending else { return }
        let room = max(0, TierState.maxUnrankedItems - tier.unranked.count)
        guard room > 0 else {
            showNote("Unranked is full")
            return
        }
        for caption in suggestions.prefix(room) {
            var cell = ChartCell()
            cell.caption = caption
            tier.unranked.append(cell)
        }
    }

    private func selectCell(_ id: UUID) {
        guard !isSending, cell(for: id) != nil else { return }
        inlineNote = nil
        selectedCell = TierCellSelection(id: id)
    }

    private func cell(for id: UUID) -> ChartCell? {
        // locate's contract is nonoptional; verify membership before calling it.
        guard itemIDs.contains(id) else { return nil }
        let location = tier.locate(id)
        if let i = location.tierIndex {
            guard tier.tiers.indices.contains(i), tier.tiers[i].items.indices.contains(location.itemIndex),
                  tier.tiers[i].items[location.itemIndex].id == id else { return nil }
            return tier.tiers[i].items[location.itemIndex]
        }
        guard tier.unranked.indices.contains(location.itemIndex), tier.unranked[location.itemIndex].id == id else { return nil }
        return tier.unranked[location.itemIndex]
    }

    private func cellBinding(for id: UUID) -> Binding<ChartCell>? {
        guard let fallback = cell(for: id) else { return nil }
        return Binding(
            get: { cell(for: id) ?? fallback },
            set: { updatedCell in
                guard !isSending, updatedCell.id == id, cell(for: id) != nil else { return }
                // Resolve again for every write, including asynchronous image attachments.
                let location = tier.locate(id)
                if let i = location.tierIndex {
                    tier.tiers[i].items[location.itemIndex] = updatedCell
                } else {
                    tier.unranked[location.itemIndex] = updatedCell
                }
            }
        )
    }

    private func destinations(for id: UUID) -> [TierMoveDestination] {
        guard cell(for: id) != nil else { return [] }
        let location = tier.locate(id)
        let currentID = location.tierIndex.map { tier.tiers[$0].id } ?? TierMoveDestination.unranked.id
        return allTiers.map { TierMoveDestination(id: $0.id, label: $0.label, isCurrent: currentID == $0.id) }
            + [TierMoveDestination(id: TierMoveDestination.unranked.id, label: "Unranked", isCurrent: location.tierIndex == nil)]
    }

    @discardableResult
    private func moveItem(_ id: UUID, to destination: UUID, at index: Int? = nil) -> Bool {
        guard !isSending, cell(for: id) != nil else { return false }
        let toUnranked = destination == TierMoveDestination.unranked.id
        guard toUnranked || tier.tiers.contains(where: { $0.id == destination }) else { return false }
        let moved = withAnimation(rowAnimation) {
            tier.moveItem(id: id, toTier: toUnranked ? nil : destination, at: index)
        }
        guard moved else {
            let label = allTiers.first(where: { $0.id == destination })?.label ?? "Unranked"
            showNote("\(label) is full")
            return false
        }
        inlineNote = nil
        announceMove(id)
        return true
    }

    private func reorderItem(_ id: UUID, direction: Int) {
        guard !isSending, cell(for: id) != nil, direction == -1 || direction == 1 else { return }
        let location = tier.locate(id)
        let count = location.tierIndex.map { tier.tiers[$0].items.count } ?? tier.unranked.count
        let destination = location.itemIndex + direction
        guard (0..<count).contains(destination) else { return }
        // Array.move uses pre-removal offsets; make one adjacent move without changing identity.
        let offset = direction > 0 ? destination + 1 : destination
        withAnimation(rowAnimation) {
            if let i = location.tierIndex {
                tier.tiers[i].items.move(fromOffsets: IndexSet(integer: location.itemIndex), toOffset: offset)
            } else {
                tier.unranked.move(fromOffsets: IndexSet(integer: location.itemIndex), toOffset: offset)
            }
        }
        announceMove(id)
    }

    private func announceMove(_ id: UUID) {
        guard let cell = cell(for: id) else { return }
        let location = tier.locate(id)
        let caption = cell.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "item" : cell.caption
        let destination: String
        let count: Int
        if let i = location.tierIndex {
            destination = "tier \(displayLabel(tier.tiers[i], index: i))"
            count = tier.tiers[i].items.count
        } else {
            destination = "Unranked"
            count = tier.unranked.count
        }
        UIAccessibility.post(notification: .announcement, argument: "Moved \(caption) to \(destination), position \(location.itemIndex + 1) of \(count)")
    }

    private func showNote(_ message: String) {
        inlineNote = TierInlineNote(message: message)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

private struct TierCellSelection: Identifiable {
    let id: UUID
}

private struct TierInlineNote: Identifiable {
    let id = UUID()
    let message: String
}
