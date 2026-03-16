/*
 * Live AI Intent
 * App Intent - Supports Siri and Shortcuts to trigger Live AI (runs in background, no unlock needed)
 */

import AppIntents
import UIKit

// MARK: - Live AI Intent (Background Mode)

@available(iOS 16.0, *)
struct LiveAIIntent: AppIntent {
    static var title: LocalizedStringResource = "Live Conversation"
    static var description = IntentDescription("Start a live multimodal conversation")
    // Must open the app because iOS has system restrictions on background recording
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Send notification to have the app automatically open the Live AI interface
        NotificationCenter.default.post(name: .liveAITriggered, object: nil)
        return .result(dialog: "Starting live conversation...")
    }
}

// MARK: - Stop Live AI Intent

@available(iOS 16.0, *)
struct StopLiveAIIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Live Conversation"
    static var description = IntentDescription("Stop the running live conversation")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = LiveAIManager.shared

        if manager.isRunning {
            await manager.stopSession()
            return .result(dialog: "Live AI stopped")
        } else {
            return .result(dialog: "Live AI is not running")
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let liveAITriggered = Notification.Name("liveAITriggered")
}
