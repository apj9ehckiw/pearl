import SwiftUI
import Combine

@main
struct PearlWalletApp: App {
    @StateObject private var wallet = WalletModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("lockImmediatelyOnBackground") private var lockImmediatelyOnBackground = false
    @State private var checkingForeground = false
    @State private var wasBackgrounded = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView().environmentObject(wallet)
                if scenePhase != .active || checkingForeground {
                    Color(.systemBackground).ignoresSafeArea()
                    Label("Pearl 钱包已锁定", systemImage: "lock.shield.fill")
                        .font(.title2).foregroundStyle(.teal)
                }
            }
            .tint(.teal)
            .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
            .task { await wallet.initialize() }
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in wallet.noteActivity() })
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidChangeNotification)) { _ in wallet.noteActivity() }
            .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidChangeNotification)) { _ in wallet.noteActivity() }
            .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
                if scenePhase == .active { Task { await wallet.lockIfExpired() } }
            }
            .onChange(of: scenePhase) { phase in
                if phase != .active { checkingForeground = true }
                if phase == .background {
                    wasBackgrounded = true
                    if lockImmediatelyOnBackground {
                        let task = UIApplication.shared.beginBackgroundTask(withName: "锁定 Pearl 钱包")
                        Task {
                            await wallet.lock()
                            if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
                        }
                    }
                } else if phase == .active {
                    let shouldLockImmediately = wasBackgrounded && lockImmediatelyOnBackground
                    Task {
                        if shouldLockImmediately { await wallet.lock() }
                        else { await wallet.lockIfExpired() }
                        wasBackgrounded = false
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
