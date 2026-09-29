import Combine
import CryptoKit
import Foundation
import Messages
import SwiftUI

@MainActor
final class ChartCoordinator: ObservableObject {
    let dailyStore = DailyStore()
    @Published private(set) var claimableChart: ChartState?
    @Published var activeContent: ChartContent?
    @Published var history: [ChartContent] = []
    @Published var isLoading = false
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published var mergeReview: ChartMergeReview?
    @Published var presentationStyle: MSMessagesAppPresentationStyle = .compact
    @Published var isCreatingNewChart = false
    @Published var unknownKindInterstitial = false

    private weak var controller: MSMessagesAppViewController?
    private weak var conversation: MSConversation?
    private var conversationScope: String?
    private var activeSession: MSSession?
    private var loadedMessageID: String?
    private var editingBase: ChartContent?
    private var editingID = UUID()
    private var draftSaveSucceeded = true

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

        // Tier-chart sync arrives in P1; the CloudKit fetch below only knows grid charts.
        guard MessageComposer.chartKind(from: message) == .grid else { return }

        Task {
            guard let incoming = try? await CloudKitChartService.shared.fetchChart(id: chartID),
                  conversationScope == newScope else { return }
            ChartHistoryStore.receive(.grid(incoming), in: newScope)
            refreshHistory()
        }
    }

    private func prepareConversation(_ conversation: MSConversation) -> String {
        let newScope = Self.scopeKey(for: conversation)
        if conversationScope != newScope {
            editingID = UUID()
            editingBase = nil
            mergeReview = nil
            activeContent = nil
            claimableChart = nil
            activeSession = nil
            loadedMessageID = nil
            isLoading = false
            isCreatingNewChart = false
            unknownKindInterstitial = false
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
        guard MessageComposer.isKnownKind(from: message) else {
            unknownKindInterstitial = true
            return
        }
        unknownKindInterstitial = false

        if let chartUUID = UUID(uuidString: chartID) {
            ChartHistoryStore.unhide(chartUUID, in: newScope)
            refreshHistory()
        }
        activeSession = message.session
        guard reloadIfAlreadySelected || loadedMessageID != chartID else { return }
        loadedMessageID = chartID
        if MessageComposer.chartKind(from: message) == .tier {
            loadTierChart(id: chartID, conversationScope: newScope)
        } else {
            loadSharedChart(id: chartID, conversationScope: newScope, completion: MessageComposer.dailyCompletion(from: message))
        }
    }

    func createDailyChart() {
        dailyStore.updateClock()
        guard let template = dailyStore.template else { return }
        if let draft = history.first(where: {
            guard case .grid(let chart) = $0 else { return false }
            return chart.daily?.day == template.day && !chart.isComplete
        }) {
            openHistory(draft)
        } else {
            createContent(.grid(template.makeChart()))
        }
    }

    func createChart() { createContent(.grid(ChartState())) }

    func createTierChart() { createContent(.tier(TierState.makeDefault())) }

    private func createContent(_ newContent: ChartContent) {
        guard !isSending else { return }
        editingID = UUID()
        editingBase = nil
        mergeReview = nil
        loadedMessageID = nil
        activeSession = nil
        isCreatingNewChart = true
        claimableChart = nil
        unknownKindInterstitial = false
        activeContent = newContent
        persistDraft(newContent)
        controller?.requestPresentationStyle(.expanded)
    }

    func openHistory(_ content: ChartContent) {
        guard !isSending else { return }
        claimableChart = nil
        editingID = UUID()
        // Read draft and ancestor together: an incoming message may have updated
        // history since the tapped card was rendered.
        let saved = ChartHistoryStore.savedVersion(for: content.id)
        editingBase = saved?.base
        mergeReview = nil
        loadedMessageID = nil
        activeSession = nil
        isCreatingNewChart = false
        unknownKindInterstitial = false
        activeContent = saved?.content ?? content
        controller?.requestPresentationStyle(.expanded)
    }

    func closeChart() {
        guard !isSending else { return }
        editingID = UUID()
        editingBase = nil
        mergeReview = nil
        activeContent = nil
        claimableChart = nil
        loadedMessageID = nil
        activeSession = nil
        isCreatingNewChart = false
        unknownKindInterstitial = false
        refreshHistory()
    }

    func persistDraft(_ draft: ChartContent) {
        guard let conversationScope else { return }
        let saved = ChartHistoryStore.save(draft, base: editingBase, in: conversationScope)
        if saved {
            draftSaveSucceeded = true
        } else if draftSaveSucceeded {
            // Alert only on the success-to-failure transition so repeated
            // failures while the user keeps editing don't spam alerts.
            draftSaveSucceeded = false
            errorMessage = "Couldn't save your draft. Your latest changes may be lost if you close the editor."
        }
        refreshHistory()
    }

    func deleteHistory(_ content: ChartContent) {
        ChartHistoryStore.delete(content.id)
        // Images may still be referenced by another draft or an unresolved conflict.
        refreshHistory()
    }

    func hideHistory(_ content: ChartContent) {
        guard let conversationScope else { return }
        ChartHistoryStore.hide(content.id, in: conversationScope)
        refreshHistory()
    }

    func saveToPhotos(_ content: ChartContent) {
        Task {
            do {
                try await ChartPhotoSaver.save(content)
            } catch {
                errorMessage = "Couldn’t save the chart to Photos. \(error.localizedDescription)"
            }
        }
    }

    func resolveConflicts(_ choices: [String: ChartConflictChoice]) {
        // Merge review is grid-only in P0 — tier charts never produce a review.
        guard let review = mergeReview,
              case .grid(let current) = activeContent,
              current.id == review.local.id else { return }
        let result = review.merged(choices: choices)
        guard result.conflicts.isEmpty else { return }
        // Choices apply only against the version actually shown. If it changes
        // again, the next upload performs a fresh merge and asks again as needed.
        editingBase = .grid(review.remote)
        activeContent = .grid(result.chart)
        persistDraft(.grid(result.chart))
        mergeReview = nil
        shareCurrentChart()
    }

    func shareCurrentChart() {
        guard !isSending else { return }
        guard let content = activeContent, let conversation, let scope = conversationScope else {
            errorMessage = "Open this app from a Messages conversation before sharing."
            return
        }
        persistDraft(content)
        let base = editingBase
        let editor = editingID
        let session = activeSession
        isSending = true

        Task {
            defer { isSending = false }
            switch content.kind {
            case .grid:
                guard case .grid(let outgoing) = content else { return }
                // editingBase is only ever a grid when the active content is one,
                // but project defensively — a kind mismatch must not crash the send.
                let chartBase: ChartState?
                if case .grid(let projected) = base {
                    chartBase = projected
                } else {
                    chartBase = nil
                }
                do {
                    // Wait for the real upload outcome. A detached timeout would let
                    // an old upload continue writing after the user retries.
                    let saved = try await CloudKitChartService.shared.upload(outgoing, base: chartBase)
                    ChartHistoryStore.save(.grid(saved), base: .grid(saved), in: scope)
                    guard editingID == editor, conversationScope == scope else { return }
                    editingBase = .grid(saved)
                    activeContent = .grid(saved)
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
            case .tier:
                guard case .tier(let tier) = content else { return }
                await tierShare(tier, conversation: conversation, session: session, editor: editor)
            }
        }
    }

    /// Tier share path: local render + message insert only. Never touches CloudKit.
    private func tierShare(_ tier: TierState, conversation: MSConversation, session: MSSession?, editor: UUID) async {
        // P1: upload TierChart record via CloudKitChartService before insert.
        guard editingID == editor, conversationScope != nil else { return }
        guard tier.rankedItemCount > 0 else {
            errorMessage = "Rank at least one item before sharing."
            return
        }
        guard let preview = TierImageRenderer.render(tier) else {
            errorMessage = "This tier chart is too large to share. Try fewer tiers or items."
            return
        }
        let message = MessageComposer.message(for: .tier(tier), image: preview, session: session)
        do {
            try await conversation.insert(message)
            guard editingID == editor else { return }
            activeSession = message.session
            controller?.dismiss()
        } catch {
            errorMessage = "Couldn’t share the tier chart. \(error.localizedDescription)"
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
                    activeContent = draft.content
                    persistDraft(draft.content)
                } else {
                    editingBase = .grid(incoming)
                    activeContent = .grid(incoming)
                    persistDraft(.grid(incoming))
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

    /// P0 loads tier charts from local history only. P1 replaces the store
    /// lookup below with a CloudKit TierChart fetch.
    private func loadTierChart(id: String, conversationScope: String) {
        isLoading = true
        controller?.requestPresentationStyle(.expanded)
        guard let uuid = UUID(uuidString: id),
              let saved = ChartHistoryStore.savedVersion(for: uuid) else {
            errorMessage = "Couldn't load this tier chart on this device yet — tier sync arrives in the next update."
            isLoading = false
            return
        }
        editingID = UUID()
        claimableChart = nil
        mergeReview = nil
        isCreatingNewChart = false
        editingBase = saved.base
        activeContent = saved.content
        persistDraft(saved.content)
        isLoading = false
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
