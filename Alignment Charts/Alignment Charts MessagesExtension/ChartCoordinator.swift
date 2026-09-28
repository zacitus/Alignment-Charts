import Combine
import CryptoKit
import Foundation
import Messages
import SwiftUI

@MainActor
final class ChartCoordinator: ObservableObject {
    let dailyStore = DailyStore()
    @Published private(set) var claimableChart: ChartState?
    @Published var chart: ChartState?
    @Published var history: [ChartState] = []
    @Published var isLoading = false
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published var mergeReview: ChartMergeReview?
    @Published var presentationStyle: MSMessagesAppPresentationStyle = .compact
    @Published var isCreatingNewChart = false

    private weak var controller: MSMessagesAppViewController?
    private weak var conversation: MSConversation?
    private var conversationScope: String?
    private var activeSession: MSSession?
    private var loadedMessageID: String?
    private var editingBase: ChartState?
    private var editingID = UUID()

    init(controller: MSMessagesAppViewController) {
        self.controller = controller
    }

    func handleActivation(_ conversation: MSConversation) {
        let newScope = prepareConversation(conversation)
        Task { await dailyStore.refresh() }

        guard let message = conversation.selectedMessage else { return }
        openSharedMessage(message, conversationScope: newScope)
    }

    func handleSelection(_ message: MSMessage, in conversation: MSConversation) {
        let newScope = prepareConversation(conversation)
        openSharedMessage(message, conversationScope: newScope, reloadIfAlreadySelected: true)
    }

    func handleReceived(_ message: MSMessage, in conversation: MSConversation) {
        let newScope = prepareConversation(conversation)
        guard let chartID = MessageComposer.chartID(from: message),
              let chartUUID = UUID(uuidString: chartID) else { return }

        ChartHistoryStore.unhide(chartUUID, in: newScope)
        refreshHistory()

        Task {
            guard let incoming = try? await CloudKitChartService.shared.fetchChart(id: chartID),
                  conversationScope == newScope else { return }
            ChartHistoryStore.receive(incoming, in: newScope)
            refreshHistory()
        }
    }

    private func prepareConversation(_ conversation: MSConversation) -> String {
        let newScope = Self.scopeKey(for: conversation)
        if conversationScope != newScope {
            editingID = UUID()
            editingBase = nil
            mergeReview = nil
            chart = nil
            claimableChart = nil
            activeSession = nil
            loadedMessageID = nil
            isLoading = false
            isCreatingNewChart = false
        }
        self.conversation = conversation
        conversationScope = newScope
        refreshHistory()
        return newScope
    }

    private func openSharedMessage(
        _ message: MSMessage,
        conversationScope newScope: String,
        reloadIfAlreadySelected: Bool = false
    ) {
        guard !isSending, let chartID = MessageComposer.chartID(from: message) else { return }

        if let chartUUID = UUID(uuidString: chartID) {
            ChartHistoryStore.unhide(chartUUID, in: newScope)
            refreshHistory()
        }
        activeSession = message.session
        guard reloadIfAlreadySelected || loadedMessageID != chartID else { return }
        loadedMessageID = chartID
        loadSharedChart(id: chartID, conversationScope: newScope, completion: MessageComposer.dailyCompletion(from: message))
    }

    func createDailyChart() {
        dailyStore.updateClock()
        guard let template = dailyStore.template else { return }
        if let draft = history.first(where: { $0.daily?.day == template.day && !$0.isComplete }) {
            openHistory(draft)
        } else {
            createChart(template.makeChart())
        }
    }

    func createChart() { createChart(ChartState()) }

    private func createChart(_ newChart: ChartState) {
        guard !isSending else { return }
        editingID = UUID()
        editingBase = nil
        mergeReview = nil
        loadedMessageID = nil
        activeSession = nil
        isCreatingNewChart = true
        claimableChart = nil
        chart = newChart
        persistDraft(newChart)
        controller?.requestPresentationStyle(.expanded)
    }

    func openHistory(_ savedChart: ChartState) {
        guard !isSending else { return }
        claimableChart = nil
        editingID = UUID()
        // Read draft and ancestor together: an incoming message may have updated
        // history since the tapped card was rendered.
        let saved = ChartHistoryStore.savedVersion(for: savedChart.id)
        editingBase = saved?.base
        mergeReview = nil
        loadedMessageID = nil
        activeSession = nil
        isCreatingNewChart = false
        chart = saved?.chart ?? savedChart
        controller?.requestPresentationStyle(.expanded)
    }

    func closeChart() {
        guard !isSending else { return }
        editingID = UUID()
        editingBase = nil
        mergeReview = nil
        chart = nil
        claimableChart = nil
        loadedMessageID = nil
        activeSession = nil
        isCreatingNewChart = false
        refreshHistory()
    }

    func persistDraft(_ draft: ChartState) {
        guard let conversationScope else { return }
        ChartHistoryStore.save(draft, base: editingBase, in: conversationScope)
        refreshHistory()
    }

    func deleteHistory(_ savedChart: ChartState) {
        ChartHistoryStore.delete(savedChart.id)
        // Images may still be referenced by another draft or an unresolved conflict.
        refreshHistory()
    }

    func hideHistory(_ savedChart: ChartState) {
        guard let conversationScope else { return }
        ChartHistoryStore.hide(savedChart.id, in: conversationScope)
        refreshHistory()
    }

    func saveToPhotos(_ savedChart: ChartState) {
        Task {
            do {
                try await ChartPhotoSaver.save(savedChart)
            } catch {
                errorMessage = "Couldn’t save the chart to Photos. \(error.localizedDescription)"
            }
        }
    }

    func resolveConflicts(_ choices: [String: ChartConflictChoice]) {
        guard let review = mergeReview, chart?.id == review.local.id else { return }
        let result = review.merged(choices: choices)
        guard result.conflicts.isEmpty else { return }
        // Choices apply only against the version actually shown. If it changes
        // again, the next upload performs a fresh merge and asks again as needed.
        editingBase = review.remote
        chart = result.chart
        persistDraft(result.chart)
        mergeReview = nil
        shareCurrentChart()
    }

    func shareCurrentChart() {
        guard !isSending else { return }
        guard let outgoing = chart, let conversation, let scope = conversationScope else {
            errorMessage = "Open this app from a Messages conversation before sharing."
            return
        }
        persistDraft(outgoing)
        let base = editingBase
        let editor = editingID
        let session = activeSession
        isSending = true

        Task {
            defer { isSending = false }
            do {
                // Wait for the real upload outcome. A detached timeout would let
                // an old upload continue writing after the user retries.
                let saved = try await CloudKitChartService.shared.upload(outgoing, base: base)
                ChartHistoryStore.save(saved, base: saved, in: scope)
                guard editingID == editor, conversationScope == scope else { return }
                editingBase = saved
                chart = saved
                refreshHistory()
                // A complete upload earns no personal credit until actually sent/tapped.
                try await DailyCloudService.shared.recordCompletion(saved)
                let preview = ChartImageRenderer.render(saved)
                let message = MessageComposer.message(for: saved, image: preview, session: session)
                try await conversation.insert(message)
                guard editingID == editor, conversationScope == scope else { return }
                activeSession = message.session
                controller?.dismiss()
            } catch let review as ChartMergeReview {
                guard editingID == editor, conversationScope == scope else { return }
                mergeReview = review
            } catch {
                guard editingID == editor, conversationScope == scope else { return }
                errorMessage = "Couldn’t share the chart. \(error.localizedDescription)"
            }
        }
    }

    func retryDailyClaim() {
        guard let incoming = claimableChart else { return }
        Task { await dailyStore.claim(incoming) }
    }

    func handleStartedSending(_ message: MSMessage, in conversation: MSConversation) {
        guard let id = MessageComposer.chartID(from: message),
              let completion = MessageComposer.dailyCompletion(from: message) else { return }
        Task {
            do {
                let sent = try await CloudKitChartService.shared.fetchChart(id: id)
                guard sent.daily == completion else { return }
                await dailyStore.claim(sent)
            } catch {
                errorMessage = "The chart was sent, but streak credit couldn’t be checked. Tap the sent chart before reset to retry."
            }
        }
    }

    private func loadSharedChart(id: String, conversationScope requestedScope: String, completion: DailyIdentity?) {
        editingID = UUID()
        let editor = editingID
        claimableChart = nil
        mergeReview = nil
        isCreatingNewChart = false
        isLoading = true
        controller?.requestPresentationStyle(.expanded)
        Task {
            do {
                let incoming = try await CloudKitChartService.shared.fetchChart(id: id)
                guard editingID == editor, conversationScope == requestedScope, loadedMessageID == id else { return }
                if let completion, incoming.daily == completion {
                    claimableChart = incoming
                    Task { await dailyStore.claim(incoming) }
                }
                if let draft = ChartHistoryStore.pendingDraft(for: incoming.id) {
                    editingBase = draft.base
                    chart = draft.chart
                    persistDraft(draft.chart)
                } else {
                    editingBase = incoming
                    chart = incoming
                    persistDraft(incoming)
                }
            } catch {
                guard editingID == editor, conversationScope == requestedScope, loadedMessageID == id else { return }
                errorMessage = "Couldn’t load this chart. \(error.localizedDescription)"
                loadedMessageID = nil
            }
            if editingID == editor, conversationScope == requestedScope {
                isLoading = false
            }
        }
    }

    private func refreshHistory() {
        guard let conversationScope else {
            history = []
            return
        }
        history = ChartHistoryStore.all(in: conversationScope)
    }

    /// Messages does not publish a conversation identifier. The stable participant UUIDs
    /// are the closest available local scope, so hash their sorted values for local storage.
    private static func scopeKey(for conversation: MSConversation) -> String {
        let participants = ([conversation.localParticipantIdentifier]
            + conversation.remoteParticipantIdentifiers)
            .map(\.uuidString)
            .sorted()
            .joined(separator: "|")
        let digest = SHA256.hash(data: Data(participants.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

}
