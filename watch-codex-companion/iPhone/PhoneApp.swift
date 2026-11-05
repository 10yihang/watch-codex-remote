import SwiftUI

@main
struct WatchCodexPhoneApp: App {
    @StateObject private var store = CompanionStore()
    var body: some Scene {
        WindowGroup { PhoneRootView().environmentObject(store).tint(.accentColor) }
    }
}
