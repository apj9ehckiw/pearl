import SwiftUI

@main
struct PearlWalletApp: App {
    @StateObject private var wallet = WalletModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("lockImmediatelyOnBackground") private var lockImmediatelyOnBackground = false
    @State private var checkingForeground = false

    init() { BackgroundNotifications.register() }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView().environmentObject(wallet)
                if scenePhase != .active || checkingForeground {
                    Color(.systemBackground).ignoresSafeArea()
                    Label("Pearl 内容已隐藏", systemImage: "eye.slash.fill")
                        .font(.title2).foregroundStyle(PearlTheme.accent)
                }
            }
            .tint(PearlTheme.accent)
            .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
            .task {
                if UIApplication.shared.applicationState != .background {
                    await wallet.initialize()
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase != .active { checkingForeground = true }
                if phase == .background {
                    wallet.enteredBackground()
                    BackgroundNotifications.schedule()
                    if lockImmediatelyOnBackground {
                        let task = UIApplication.shared.beginBackgroundTask(withName: "锁定 Pearl 钱包")
                        Task {
                            await wallet.lock()
                            if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
                        }
                    }
                } else if phase == .active {
                    let returnedAt = Date()
                    Task {
                        if !wallet.initialized { await wallet.initialize() }
                        await wallet.lockAfterBackground(immediately: lockImmediatelyOnBackground,
                            now: returnedAt)
                        checkingForeground = false
                    }
                }
            }
            .alert("Pearl 钱包", isPresented: Binding(get: { wallet.error != nil }, set: { if !$0 { wallet.error = nil } })) {
                Button("确定") { wallet.error = nil }
            } message: { Text(wallet.error ?? "") }
        }
    }
}
