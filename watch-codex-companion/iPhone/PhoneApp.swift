import SwiftUI

@main
struct WatchCodexPhoneApp: App {
    @StateObject private var store = CompanionStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            TabView {
                LiveRemoteView(controller: store.live.controller).tabItem { Label("真实连接", systemImage: "network") }
                PhoneRootView().environmentObject(store).tabItem { Label("演示", systemImage: "play.rectangle") }
            }.tint(.accentColor)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { store.live.controller.applicationDidEnterBackground() }
                }
        }
    }
}
