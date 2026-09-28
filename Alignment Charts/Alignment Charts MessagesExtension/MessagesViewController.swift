//
//  MessagesViewController.swift
//  Alignment Charts MessagesExtension
//

import UIKit
import SwiftUI
import Messages
import Combine

class MessagesViewController: MSMessagesAppViewController {

    private lazy var coordinator = ChartCoordinator(controller: self)
    private var hostingController: UIHostingController<RootView>?
    private var cancellables = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let hosting = UIHostingController(rootView: RootView(coordinator: coordinator))
        hostingController = hosting
        hosting.safeAreaRegions = .container
        hosting.view.backgroundColor = .systemBackground
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        coordinator.$chart
            .map { $0 == nil }
            .removeDuplicates()
            .sink { [weak hosting] isShowingHome in
                // Messages can leave a stale keyboard region active when the extension
                // replaces the keyboard. Exclude that region on the non-editing home
                // screen, but restore normal keyboard avoidance inside the chart editor.
                hosting?.safeAreaRegions = isShowingHome ? .container : .all
                hosting?.view.setNeedsLayout()
            }
            .store(in: &cancellables)

        #if DEBUG
        Task {
            do {
                try await CloudKitChartService.shared.initializeDevelopmentSchema()
                print("Alignment Charts: development CloudKit schema initialized")
            } catch {
                print("Alignment Charts: CloudKit schema bootstrap failed: \(error)")
            }
        }
        #endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        hostingController?.view.frame = view.bounds
    }

    override func willBecomeActive(with conversation: MSConversation) {
        coordinator.handleActivation(conversation)
    }

    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        coordinator.handleSelection(message, in: conversation)
    }

    override func didStartSending(_ message: MSMessage, conversation: MSConversation) {
        coordinator.handleStartedSending(message, in: conversation)
    }

    override func didReceive(_ message: MSMessage, conversation: MSConversation) {
        coordinator.handleReceived(message, in: conversation)
    }

    override func willTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        coordinator.presentationStyle = presentationStyle
    }
}
