import SwiftUI
import WatchKit
import WatchConnectivity

@main
struct WatchCodexWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchDelegate.self) var delegate
    @StateObject private var store = CompanionStore()
    var body: some Scene {
        WindowGroup { WatchRootView().environmentObject(store).tint(watchAccent).accentColor(watchAccent)
                .environment(\.colorScheme, .dark) }
    }
}

final class WatchDelegate: NSObject, WKApplicationDelegate {
    private var pendingConnectivityTasks: [WKWatchConnectivityRefreshBackgroundTask] = []
    private var activationObservation: NSKeyValueObservation?
    private var contentObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching() {
        // CompanionStore owns the WCSession delegate. Observe without replacing it.
        let session = WCSession.default
        activationObservation = session.observe(\.activationState, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.completeConnectivityTasksIfReady() }
        }
        contentObservation = session.observe(\.hasContentPending, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.completeConnectivityTasksIfReady() }
        }
    }
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let connectivityTask = task as? WKWatchConnectivityRefreshBackgroundTask {
                pendingConnectivityTasks.append(connectivityTask)
            } else if let snapshotTask = task as? WKSnapshotRefreshBackgroundTask {
                snapshotTask.setTaskCompleted(restoredDefaultState: true, estimatedSnapshotExpiration: .distantFuture, userInfo: nil)
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
        completeConnectivityTasksIfReady()
    }
    private func completeConnectivityTasksIfReady() {
        let session = WCSession.default
        guard session.activationState == .activated, !session.hasContentPending else { return }
        for task in pendingConnectivityTasks { task.setTaskCompletedWithSnapshot(false) }
        pendingConnectivityTasks.removeAll()
    }
}
