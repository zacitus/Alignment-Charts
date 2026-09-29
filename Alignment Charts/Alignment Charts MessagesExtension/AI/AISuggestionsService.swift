import FoundationModels
import Foundation

@Generable
struct SuggestionList {
    @Guide(description: "Distinct, concise item names, no numbering or extra text")
    var items: [String]
}

struct AISuggestionsService {
    static let minSuggestionCount = 4
    static let maxSuggestionCount = 16

    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    func suggestions(for topic: String, count: Int) async throws -> [String] {
        let cleanTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTopic.isEmpty else {
            throw AISuggestionsError("Type a topic first, like \"fast food restaurants\".")
        }
        let targetCount = min(max(count, Self.minSuggestionCount), Self.maxSuggestionCount)
        guard Self.isAvailable else {
            throw AISuggestionsError("AI suggestions aren't available on this device right now.")
        }

        let session = LanguageModelSession(instructions:
            "You generate short list items for ranking charts. Each item is a short name, no numbering, no extra text.")
        do {
            let response = try await session.respond(
                to: "List exactly \(targetCount) distinct \(cleanTopic) that people commonly rank.",
                generating: SuggestionList.self
            )
            let items = Self.postProcess(response.content.items, count: targetCount)
            guard !items.isEmpty else {
                throw AISuggestionsError("Couldn't come up with suggestions. Try a different topic.")
            }
            return items
        } catch let error as AISuggestionsError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.mapError(error)
        }
    }

    private static func postProcess(_ items: [String], count: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in items {
            var item = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // Strip leading numbering (e.g. "1. " or "2) ") in case the model numbers items anyway.
            if let range = item.range(of: #"^\d+[.)]\s*"#, options: .regularExpression) {
                item.removeSubrange(range)
                item = item.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !item.isEmpty else { continue }
            let key = item.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(item)
            if result.count == count { break }
        }
        return result
    }

    private static func mapError(_ error: Error) -> AISuggestionsError {
        // IMPORTANT: do NOT reference LanguageModelSession.GenerationError or LanguageModelError
        // by name. The concrete generation-error enum changed names between the iOS 26 SDK
        // (GenerationError) and the iOS 27 SDK (LanguageModelError), and this target deploys
        // to 26.2, so naming either type is a compile risk. Detect guardrail/refusal by
        // description instead, which is stable across SDKs.
        let description = String(describing: error).lowercased()
        if description.contains("guardrail") || description.contains("refusal") {
            return AISuggestionsError("I can't make suggestions for that topic. Try a different one.")
        }
        return AISuggestionsError("Couldn't generate suggestions. Please try again.")
    }
}

struct AISuggestionsError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }

    init(_ message: String) {
        self.message = message
    }
}
