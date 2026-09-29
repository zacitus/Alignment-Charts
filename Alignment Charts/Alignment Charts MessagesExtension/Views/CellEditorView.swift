import PhotosUI
import SwiftUI

struct TierMoveDestination: Identifiable {
    var id: UUID
    var label: String
    var isCurrent: Bool

    static let unranked = TierMoveDestination(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
        label: "Unranked",
        isCurrent: false
    )
}

struct CellEditorView: View {
    @Binding var cell: ChartCell
    var moveDestinations: [TierMoveDestination]? = nil
    var onMoveToTier: ((UUID) -> Void)? = nil
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
                if let moveDestinations, let onMoveToTier {
                    Section("Move to Tier") {
                        ForEach(moveDestinations) { destination in
                            Button { onMoveToTier(destination.id) } label: {
                                HStack {
                                    Text(destination.label)
                                    Spacer()
                                    if destination.isCurrent {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            .accessibilityValue(destination.isCurrent ? "Current tier" : "")
                        }
                    }
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
