import SwiftUI

@main
struct PearlWalletApp: App {
    @StateObject private var wallet = WalletModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView().environmentObject(wallet)
                if scenePhase != .active {
                    Color(.systemBackground).ignoresSafeArea()
                    Label("Pearl Wallet", systemImage: "lock.shield.fill")
                        .font(.title2).foregroundStyle(.teal)
                }
            }
            .tint(.teal)
            .task { await wallet.initialize() }
            .onChange(of: scenePhase) { phase in
                if phase == .background {
                    let task = UIApplication.shared.beginBackgroundTask(withName: "Close Pearl wallet")
                    Task {
                        await wallet.lock()
                        if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
                    }
                }
            }
            .alert("Pearl Wallet", isPresented: Binding(get: { wallet.error != nil }, set: { if !$0 { wallet.error = nil } })) {
                Button("OK") { wallet.error = nil }
            } message: { Text(wallet.error ?? "") }
        }
    }
}
