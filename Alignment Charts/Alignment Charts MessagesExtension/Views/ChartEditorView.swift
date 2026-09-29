import PhotosUI
import SwiftUI

struct ChartEditorView: View {
    @Binding var chart: ChartState
    let isNewChart: Bool
    let isSending: Bool
    let onClose: () -> Void
    let onShare: () -> Void
    let dailyStore: DailyStore
    let canClaimDaily: Bool
    let onClaimDaily: () -> Void

    @State private var selectedCell: CellSelection?
    @State private var isSaveFeedbackActive = false
    @State private var isLayoutExpanded: Bool

    private let canvasColor = Color(uiColor: .systemBackground)
    private let inkColor = Color(uiColor: .label)
    private let gridLabelWidth: CGFloat = 72
    private let gridCellWidth: CGFloat = 92

    init(
        chart: Binding<ChartState>,
        isNewChart: Bool,
        isSending: Bool,
        onClose: @escaping () -> Void,
        onShare: @escaping () -> Void,
        dailyStore: DailyStore,
        canClaimDaily: Bool,
        onClaimDaily: @escaping () -> Void
    ) {
        _chart = chart
        self.isNewChart = isNewChart
        self.isSending = isSending
        self.onClose = onClose
        self.onShare = onShare
        self.dailyStore = dailyStore
        self.canClaimDaily = canClaimDaily
        self.onClaimDaily = onClaimDaily
        _isLayoutExpanded = State(initialValue: isNewChart)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let daily = chart.daily {
                        DailyEditorBanner(store: dailyStore, daily: daily,
                                          canClaim: canClaimDaily, retry: onClaimDaily)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text(chart.title).font(.largeTitle.bold()).padding(.top, 12)
                    } else {
                        titleSection.padding(.top, 12)
                        layoutSection.padding(.top, 16)
                    }
                    chartSection.padding(.top, 26)
                }
                .padding()
            }
            .disabled(isSending)
            .background(canvasColor)
            .foregroundStyle(inkColor)
            .tint(inkColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                    .disabled(isSending)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isNewChart && !hasEnteredContent {
                        Button("Use default layout", action: applyDefaultLayout)
                            .tint(.blue)
                    } else {
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
            }
            .sheet(item: $selectedCell) { selection in
                CellEditorView(cell: $chart.cells[selection.index])
            }
        }
    }

    private var titleSection: some View {
        TextField("Untitled chart", text: $chart.title)
            .font(.largeTitle.bold())
            .textFieldStyle(.plain)
    }

    private var layoutSection: some View {
        DisclosureGroup("Layout", isExpanded: $isLayoutExpanded) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    axisControl(
                        placeholder: "Row title (optional)",
                        text: $chart.rowAxisTitle,
                        value: chart.rows
                    ) { chart.setRows($0) }
                    axisControl(
                        placeholder: "Column title (optional)",
                        text: $chart.columnAxisTitle,
                        value: chart.columns
                    ) { chart.setColumns($0) }
                }

                labelsSection
            }
            .padding(.top, 16)
        }
        .font(.headline)
    }

    private var labelsSection: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                ForEach(chart.rowLabels.indices, id: \.self) { index in
                    TextField("Row \(index + 1)", text: $chart.rowLabels[index])
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .frame(height: 40)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
            VStack(spacing: 8) {
                ForEach(chart.columnLabels.indices, id: \.self) { index in
                    TextField("Column \(index + 1)", text: $chart.columnLabels[index])
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .frame(height: 40)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
        }
        .font(.body)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chart")
                        .font(.headline)
                    Text("Tap any cell to add text and/or a photo.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 52)
                .opacity(isSaveFeedbackActive ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: isSaveFeedbackActive)

                ChartSaveButton(
                    content: .grid(chart),
                    onActivityChange: { isSaveFeedbackActive = $0 }
                )
                    .font(.title2)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                interactiveGrid
                    .padding(.bottom, 6)
            }
            .padding(.top, 14)
        }
    }

    private var interactiveGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: gridLabelWidth, height: 42)
                ForEach(Array(chart.columnLabels.enumerated()), id: \.offset) { index, label in
                    Text(label.isEmpty ? "Column \(index + 1)" : label)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(width: gridCellWidth, height: 42)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            ForEach(0..<chart.rows, id: \.self) { row in
                HStack(spacing: 0) {
                    Text(chart.rowLabels[row].isEmpty ? "Row \(row + 1)" : chart.rowLabels[row])
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(width: gridLabelWidth, height: 96)
                    ForEach(0..<chart.columns, id: \.self) { column in
                        let index = chart.cellIndex(row: row, column: column)
                        Button { selectedCell = CellSelection(index: index) } label: {
                            ChartCellContent(cell: chart.cells[index], showsAddLabel: true)
                                .frame(width: gridCellWidth, height: 96)
                                .background(canvasColor)
                        }
                        .buttonStyle(.plain)
                        .overlay(Rectangle().stroke(inkColor, lineWidth: 1))
                        .accessibilityLabel("Row \(row + 1), column \(column + 1)")
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .foregroundStyle(inkColor)
    }

    private var hasEnteredContent: Bool {
        let textValues = [chart.title, chart.rowAxisTitle, chart.columnAxisTitle]
            + chart.rowLabels
            + chart.columnLabels
        return textValues.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || chart.filledCellCount > 0
    }

    private func applyDefaultLayout() {
        chart.setRows(3)
        chart.setColumns(3)
        chart.rowLabels = ["Good", "Neutral", "Evil"]
        chart.columnLabels = ["Lawful", "Neutral", "Chaotic"]
    }

    private func axisControl(
        placeholder: String,
        text: Binding<String>,
        value: Int,
        update: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(placeholder, text: text)
                .font(.body)
                .textFieldStyle(.plain)
                .lineLimit(1)
            Stepper(
                value: Binding(
                    get: { value },
                    set: { newValue in
                        withAnimation(.easeInOut(duration: 0.28)) {
                            update(newValue)
                        }
                    }
                ),
                in: ChartState.sizeRange
            ) {
                EmptyView()
            }
            .labelsHidden()
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CellSelection: Identifiable {
    let index: Int
    var id: Int { index }
}

