import SwiftUI

struct AISuggestionsSheet: View {
    var onGenerate: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var topic = ""
    @State private var itemCount = 8
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var generationTask: Task<Void, Never>?

    private let service = AISuggestionsService()

    private var cleanTopic: String {
        topic.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Topic") {
                    TextField("fast food restaurants", text: $topic)
                }
                Section {
                    Stepper("Items: \(itemCount)", value: $itemCount, in: AISuggestionsService.minSuggestionCount...AISuggestionsService.maxSuggestionCount)
                }
                if isGenerating {
                    Section {
                        ProgressView("Generating suggestions...")
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("AI Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        generationTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") { generate() }
                        .disabled(isGenerating || cleanTopic.isEmpty)
                }
            }
            .onDisappear { generationTask?.cancel() }
        }
    }

    private func generate() {
        guard !isGenerating, !cleanTopic.isEmpty else { return }
        isGenerating = true
        errorMessage = nil
        generationTask = Task { @MainActor in
            defer {
                isGenerating = false
                generationTask = nil
            }
            do {
                let items = try await service.suggestions(for: cleanTopic, count: itemCount)
                try Task.checkCancellation()
                onGenerate(items)
                dismiss()
            } catch is CancellationError {
                // Dismissed mid-generation; nothing to report.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
