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
                    chart: chart,
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

private struct CellEditorView: View {
    @Binding var cell: ChartCell
    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?
    @State private var imageRevision = UUID()
    @State private var imageError: String?
    @State private var imageSelection: ImageSearchResult?
    @State private var confirmationRequested = false

    private var isAttachingImage: Bool {
        imageSelection != nil || photoItem != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextField("Name, character, or description", text: $cell.caption, axis: .vertical)
                        .lineLimit(2...5)
                }
                ImageSuggestionsView(
                    caption: cell.caption,
                    selectedResultID: cell.imageSearchResultID,
                    attachingResultID: imageSelection?.id
                ) { result in
                    imageError = nil
                    imageSelection = result
                }
                Section("Photo") {
                    if cell.hasImage, let image = ImageStore.image(for: cell.imageStorageID) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 260)
                            .id(imageRevision)
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(cell.hasImage ? "Replace Photo" : "Choose from Photos", systemImage: "photo")
                    }
                    if cell.hasImage {
                        Button("Remove Photo", role: .destructive) {
                            cell.setImageReference(nil)
                        }
                    }
                }
            }
            .disabled(isAttachingImage)
            .interactiveDismissDisabled(isAttachingImage)
            .navigationTitle("Edit Cell")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Couldn’t save photo", isPresented: Binding(
                get: { imageError != nil },
                set: { if !$0 { imageError = nil } }
            )) {
                Button("OK", role: .cancel) { imageError = nil }
            } message: {
                Text(imageError ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if confirmationRequested {
                        ProgressView().accessibilityLabel("Attaching photo")
                    } else {
                        Button("Done") {
                            if isAttachingImage {
                                confirmationRequested = true
                            } else {
                                dismiss()
                            }
                        }
                    }
                }
            }
            .task(id: imageSelection?.id) {
                guard let imageSelection else { return }
                defer {
                    self.imageSelection = nil
                    finishConfirmation()
                }
                do {
                    let image = try await ImageSearchService.image(for: imageSelection)
                    try Task.checkCancellation()
                    saveImage(image, searchResultID: imageSelection.id)
                } catch {
                    guard !Task.isCancelled else { return }
                    imageError = "Couldn’t add that image. Check your connection or try another result."
                }
            }
            .task(id: photoItem) {
                guard let photoItem else { return }
                imageError = nil
                defer {
                    self.photoItem = nil
                    finishConfirmation()
                }
                do {
                    guard let data = try await photoItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
                    try Task.checkCancellation()
                    saveImage(image)
                } catch {
                    guard !Task.isCancelled else { return }
                    imageError = "Couldn’t load that photo. Please try another image."
                }
            }
        }
    }

    private func finishConfirmation() {
        guard confirmationRequested else { return }
        confirmationRequested = false
        if !Task.isCancelled && imageError == nil {
            dismiss()
        }
    }

    private func saveImage(_ image: UIImage, searchResultID: String? = nil) {
        let imageID = UUID()
        guard ImageStore.save(image, for: imageID) else {
            imageError = "The image couldn’t be saved. Check available storage and try again."
            return
        }
        cell.setImageReference(imageID)
        cell.imageSearchResultID = searchResultID
        imageRevision = UUID()
    }
}
