import SafariServices
import SwiftUI

struct ImageSuggestionsView: View {
    let caption: String
    let selectedResultID: String?
    let attachingResultID: String?
    let onSelect: (ImageSearchResult) -> Void
    @State private var results: [ImageSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var retryID = 0
    @State private var source: ImageSearchResult?
    @State private var completedQuery = ""

    private var query: String {
        String(caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
    }

    var body: some View {
        Section {
            if query.count < 2 {
                Text("Type a name or description above to find images.")
                    .foregroundStyle(.secondary)
            } else if isSearching || completedQuery != query {
                ProgressView("Finding images…")
            } else if results.isEmpty && errorMessage == nil {
                Text("No images found. Try a different name or choose from Photos.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(results) { result in
                            VStack(alignment: .leading, spacing: 6) {
                                Button { onSelect(result) } label: {
                                    AsyncImage(url: result.imageURL) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable().scaledToFill()
                                        case .failure:
                                            Image(systemName: "photo.badge.exclamationmark")
                                                .foregroundStyle(.secondary)
                                        default:
                                            ProgressView()
                                        }
                                    }
                                    .frame(width: 128, height: 120)
                                    .background(.quaternary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(alignment: .topTrailing) {
                                        if selectedResultID == result.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.title2.weight(.semibold))
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, .blue)
                                                .padding(6)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                    .overlay {
                                        if attachingResultID == result.id {
                                            ProgressView().padding(10).background(.regularMaterial, in: Circle())
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(attachingResultID != nil)
                                .accessibilityLabel("Add image: \(result.title)")
                                .accessibilityAddTraits(selectedResultID == result.id ? .isSelected : [])
                                Text(result.title).font(.caption).lineLimit(2)
                                Button(result.provider) { source = result }
                                    .font(.caption2).tint(.blue)
                                    .accessibilityLabel("Image source and rights: \(result.title)")
                            }
                            .frame(width: 128, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.secondary)
                Button("Try Again") { retryID += 1 }
            }
        } header: {
            Text("Find an image")
        } footer: {
            Text("Tap an image to add it. Results from Wikipedia and Wikimedia Commons; source links include image rights.")
        }
        .task(id: SearchID(query: query, retry: retryID)) {
            results = []
            errorMessage = nil
            isSearching = query.count >= 2
            guard query.count >= 2 else { completedQuery = query; return }
            let requestedQuery = query
            do {
                try await Task.sleep(for: .milliseconds(450))
                let found = try await ImageSearchService.search(requestedQuery)
                try Task.checkCancellation()
                results = found
                completedQuery = requestedQuery
                isSearching = false
            } catch {
                guard !Task.isCancelled else { return }
                completedQuery = requestedQuery
                isSearching = false
                errorMessage = "Couldn’t search for images. Check your connection and try again."
            }
        }
        .sheet(item: $source) { result in
            ImageSourceView(url: result.sourceURL)
        }
    }

    private struct SearchID: Equatable {
        let query: String
        let retry: Int
    }
}

private struct ImageSourceView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
