import SwiftUI

struct RootView: View {
    @ObservedObject var coordinator: ChartCoordinator

    var body: some View {
        Group {
            if coordinator.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading chart…")
                        .foregroundStyle(.secondary)
                }
            } else if coordinator.unknownKindInterstitial {
                VStack(spacing: 16) {
                    Text("This chart needs a newer version of Alignment Charts.")
                        .multilineTextAlignment(.center)
                    Button("Close", action: coordinator.closeChart)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let content = coordinator.activeContent {
                switch content {
                case .grid(let visibleChart):
                    ChartEditorView(
                        chart: Binding(
                            get: {
                                guard case .grid(let chart) = coordinator.activeContent else { return visibleChart }
                                return chart
                            },
                            set: { updatedChart in
                                guard coordinator.activeContent != nil, !coordinator.isSending, coordinator.mergeReview == nil else { return }
                                guard case .grid(let current) = coordinator.activeContent, current.id == visibleChart.id else { return }
                                let touched = ChartContent.grid(updatedChart).withUpdatedAt(.now)
                                coordinator.activeContent = touched
                                coordinator.persistDraft(touched)
                            }
                        ),
                        isNewChart: coordinator.isCreatingNewChart,
                        isSending: coordinator.isSending,
                        onClose: coordinator.closeChart,
                        onShare: coordinator.shareCurrentChart,
                        dailyStore: coordinator.dailyStore,
                        canClaimDaily: coordinator.claimableChart?.id == visibleChart.id,
                        onClaimDaily: coordinator.retryDailyClaim
                    )
                case .tier(let visibleTier):
                    TierEditorView(
                        tier: Binding(
                            get: {
                                guard case .tier(let tier) = coordinator.activeContent else { return visibleTier }
                                return tier
                            },
                            set: { updatedTier in
                                guard coordinator.activeContent != nil, !coordinator.isSending, coordinator.mergeReview == nil else { return }
                                guard case .tier(let current) = coordinator.activeContent, current.id == visibleTier.id else { return }
                                let touched = ChartContent.tier(updatedTier).withUpdatedAt(.now)
                                coordinator.activeContent = touched
                                coordinator.persistDraft(touched)
                            }
                        ),
                        isNewChart: coordinator.isCreatingNewChart,
                        isSending: coordinator.isSending,
                        onClose: coordinator.closeChart,
                        onShare: coordinator.shareCurrentChart
                    )
                }
            } else {
                ChartHomeView(coordinator: coordinator)
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .sheet(item: $coordinator.mergeReview) { review in
            ChartConflictView(
                review: review,
                onResolve: coordinator.resolveConflicts,
                onCancel: { coordinator.mergeReview = nil }
            )
        }
        .alert("Alignment Charts", isPresented: Binding(
            get: { coordinator.errorMessage != nil },
            set: { if !$0 { coordinator.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { coordinator.errorMessage = nil }
        } message: {
            Text(coordinator.errorMessage ?? "")
        }
    }
}

private struct ChartHomeView: View {
    @ObservedObject var coordinator: ChartCoordinator

    @State private var showsNewChartDialog = false

    private func isComplete(_ content: ChartContent) -> Bool {
        switch content {
        case .grid(let chart): return chart.isComplete
        case .tier(let tier): return tier.isFullyRanked
        }
    }

    private var completedCharts: [ChartContent] {
        coordinator.history.filter { isComplete($0) }
    }

    private var inProgressCharts: [ChartContent] {
        coordinator.history.filter { !isComplete($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    DailyHomeSection(store: coordinator.dailyStore,
                                     onStart: coordinator.createDailyChart)
                    chartSection(
                        title: "In Progress",
                        systemImage: "pencil.line",
                        charts: inProgressCharts,
                        showsSaveButton: false,
                        emptyTitle: "No drafts in progress",
                        emptyMessage: "Unfinished charts wait here until you come back to them."
                    )
                    chartSection(
                        title: "Completed",
                        systemImage: "checkmark.rectangle",
                        charts: completedCharts,
                        showsSaveButton: true,
                        emptyTitle: "No completed charts yet",
                        emptyMessage: "Charts from this conversation move here when every cell is filled."
                    )
                }
                .padding(.vertical, 12)
                .padding(.bottom, 80)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay(alignment: .bottom) {
            Button { showsNewChartDialog = true } label: {
                Label("New Chart", systemImage: "plus.square")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
            .foregroundStyle(.white)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .confirmationDialog("New chart", isPresented: $showsNewChartDialog, titleVisibility: .visible) {
            Button(action: coordinator.createChart) {
                Label("Alignment chart", systemImage: "square.grid.3x3")
            }
            Button(action: coordinator.createTierChart) {
                Label("Tier chart", systemImage: "list.bullet.rectangle")
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private func chartSection(
        title: String,
        systemImage: String,
        charts: [ChartContent],
        showsSaveButton: Bool,
        emptyTitle: String,
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(title) (\(charts.count))", systemImage: systemImage)
                .font(.footnote.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    if charts.isEmpty {
                        ChartCarouselEmptyState(title: emptyTitle, message: emptyMessage)
                    } else {
                        ForEach(charts) { chart in
                            ChartCardView(
                                content: chart,
                                showsSaveButton: showsSaveButton,
                                onOpen: { coordinator.openHistory(chart) }
                            )
                            .contextMenu {
                                Button {
                                    coordinator.saveToPhotos(chart)
                                } label: {
                                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                                }

                                Button {
                                    coordinator.hideHistory(chart)
                                } label: {
                                    Label("Hide", systemImage: "eye.slash")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 1)
            }
        }
    }
}

private struct ChartCardView: View {
    let content: ChartContent
    let showsSaveButton: Bool
    let onOpen: () -> Void

    @State private var isSaveFeedbackActive = false

    private var displayTitle: String {
        content.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled Chart"
            : content.title
    }

    private var progressText: String? {
        switch content {
        case .grid(let chart):
            return chart.isComplete ? nil : "\(max(chart.cells.count - chart.filledCellCount, 0)) left"
        case .tier(let tier):
            return "\(tier.rankedItemCount) of \(tier.totalItemCount) ranked"
        }
    }

    @ViewBuilder private var thumbnail: some View {
        switch content {
        case .grid(let chart): ChartThumbnailView(chart: chart)
        case .tier(let tier):
            TierThumbnailView(tier: tier)
                .overlay(alignment: .topLeading) {
                    TierBadge().padding(6)
                }
        }
    }

    private var accessibilityHint: String {
        switch content {
        case .grid: return "Opens this alignment chart"
        case .tier: return "Opens this tier chart"
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 0) {
                    thumbnail
                        .frame(height: 144)
                        .frame(maxWidth: .infinity)
                        .background(Color(uiColor: .secondarySystemBackground))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(displayTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        HStack(spacing: 7) {
                            if let progressText {
                                Text(progressText)
                                    .foregroundStyle(.blue)
                                Text("|")
                                    .foregroundStyle(.tertiary)
                            }
                            Text(content.updatedAt, format: .relative(presentation: .named))
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                    .opacity(isSaveFeedbackActive ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: isSaveFeedbackActive)
                    .padding(14)
                    .padding(.trailing, showsSaveButton ? 44 : 0)
                }
                .frame(width: 264)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color(uiColor: .separator), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(displayTitle)
            .accessibilityHint(accessibilityHint)

            if showsSaveButton {
                ChartSaveButton(
                    content: content,
                    onActivityChange: { isSaveFeedbackActive = $0 }
                )
                    .font(.title2)
                    .padding(14)
            }
        }
        .frame(width: 264)
    }
}

private struct ChartThumbnailView: View {
    let chart: ChartState

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(geometry.size.width - 32, 1)
            let availableHeight = max(geometry.size.height - 28, 1)
            let labelWidth = min(44, availableWidth * 0.22)
            let headerHeight = min(24, availableHeight * 0.22)
            let cellWidth = (availableWidth - labelWidth) / CGFloat(max(chart.columns, 1))
            let cellHeight = (availableHeight - headerHeight) / CGFloat(max(chart.rows, 1))

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: labelWidth, height: headerHeight)
                    ForEach(Array(chart.columnLabels.enumerated()), id: \.offset) { index, label in
                        Text(label.isEmpty ? "C\(index + 1)" : label)
                            .font(.system(size: 5, weight: .semibold))
                            .foregroundStyle(.black)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(width: cellWidth, height: headerHeight)
                    }
                }

                ForEach(0..<chart.rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        Text(chart.rowLabels[row].isEmpty ? "R\(row + 1)" : chart.rowLabels[row])
                            .font(.system(size: 5, weight: .semibold))
                            .foregroundStyle(.black)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(width: labelWidth, height: cellHeight)

                        ForEach(0..<chart.columns, id: \.self) { column in
                            let cell = chart.cells[chart.cellIndex(row: row, column: column)]
                            ChartThumbnailCell(cell: cell)
                                .frame(width: cellWidth, height: cellHeight)
                                .overlay(Rectangle().stroke(.gray.opacity(0.7), lineWidth: 0.5))
                        }
                    }
                }
            }
            .frame(width: availableWidth, height: availableHeight)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .environment(\.colorScheme, .light)
    }
}

private struct ChartThumbnailCell: View {
    let cell: ChartCell

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.white
                if cell.hasImage, let image = ImageStore.image(for: cell.imageStorageID) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                if !cell.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(cell.caption)
                        .font(.system(size: 5, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(cell.hasImage ? .white : .black)
                        .padding(2)
                        .frame(maxWidth: .infinity)
                        .background(cell.hasImage ? Color.black.opacity(0.62) : .clear)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }
}

private struct ChartCarouselEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.3x3")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(width: 320, height: 184)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .separator), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
        }
        .accessibilityElement(children: .combine)
    }
}
