import SwiftUI

@main
struct CryptoTrackerAppApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.openURL) private var openURL

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    handleURL(url)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "cryptotracker" else { return }
        let host = url.host ?? ""
        switch host {
        case "open":
            break // already open
        case "refresh":
            Task { await appState.refreshPrices() }
        case "add-trade":
            if let comp = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = comp.queryItems {
                var params: [String: String] = [:]
                for item in queryItems { if let v = item.value { params[item.name] = v } }
                appState.addTradeFromURL(params: params)
            }
        default:
            break
        }
    }
}
