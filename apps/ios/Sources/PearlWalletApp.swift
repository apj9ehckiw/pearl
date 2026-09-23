import SwiftUI

@main
struct PearlWalletApp: App {
    @StateObject private var wallet = WalletModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView().environmentObject(wallet)
                if scenePhase != .active {
                    Color(.systemBackground).ignoresSafeArea()
                    Label("Pearl 钱包已锁定", systemImage: "lock.shield.fill")
                        .font(.title2).foregroundStyle(.teal)
                }
            }
            .tint(.teal)
            .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
            .task { await wallet.initialize() }
            .onChange(of: scenePhase) { phase in
                if phase == .background {
                    let task = UIApplication.shared.beginBackgroundTask(withName: "锁定 Pearl 钱包")
                    Task {
                        await wallet.lock()
                        if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
                    }
                }
            }
            .alert("Pearl 钱包", isPresented: Binding(get: { wallet.error != nil }, set: { if !$0 { wallet.error = nil } })) {
                Button("确定") { wallet.error = nil }
            } message: { Text(wallet.error ?? "") }
        }
    }
}
