import Photos
import SwiftUI

struct ChartSaveButton: View {
    let chart: ChartState
    var onActivityChange: (Bool) -> Void = { _ in }

    @State private var saveState = SaveState.ready

    var body: some View {
        Button(action: saveChartToPhotos) {
            Group {
                switch saveState {
                case .ready:
                    Image(systemName: "square.and.arrow.down")
                case .saving:
                    ProgressView()
                case .saved:
                    Label("Saved to Photos", systemImage: "checkmark")
                case .failed:
                    Label("Couldn't Save", systemImage: "exclamationmark.triangle")
                }
            }
            .id(saveState)
            .transition(.opacity)
            .fixedSize()
            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
        .disabled(saveState != .ready)
        .accessibilityLabel(saveState.accessibilityLabel)
    }

    private func saveChartToPhotos() {
        onActivityChange(true)
        withAnimation(.easeInOut(duration: 0.2)) {
            saveState = .saving
        }

        Task {
            do {
                try await ChartPhotoSaver.save(chart)
                await showSaveResult(.saved)
            } catch {
                await showSaveResult(.failed)
            }
        }
    }

    private func showSaveResult(_ result: SaveState) async {
        withAnimation(.easeInOut(duration: 0.2)) {
            saveState = result
        }
        try? await Task.sleep(for: .seconds(1.6))
        withAnimation(.easeInOut(duration: 0.2)) {
            saveState = .ready
        }
        onActivityChange(false)
    }
}

@MainActor
enum ChartPhotoSaver {
    private enum SaveError: LocalizedError {
        case accessDenied
        case renderingFailed

        var errorDescription: String? {
            switch self {
            case .accessDenied: "Allow Photos access to save alignment charts."
            case .renderingFailed: "The chart image couldn’t be created."
            }
        }
    }

    static func save(_ chart: ChartState) async throws {
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            throw SaveError.accessDenied
        }
        guard let image = ChartImageRenderer.render(chart) else {
            throw SaveError.renderingFailed
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
}

private enum SaveState: Hashable {
    case ready
    case saving
    case saved
    case failed

    var accessibilityLabel: String {
        switch self {
        case .ready: "Save chart to Photos"
        case .saving: "Saving chart to Photos"
        case .saved: "Saved to Photos"
        case .failed: "Couldn't save to Photos"
        }
    }
}
