import BackgroundTasks
import Foundation
import UserNotifications

enum BackgroundNotifications {
    static let taskID = "app.pearlwallet.ios.refresh"
    private static let enabledKey = "backgroundNotificationsEnabled"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let work = Task {
                let success = await runRefresh()
                refresh.setTaskCompleted(success: success)
                schedule()
            }
            refresh.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
    }

    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch { return false }
    }

    @MainActor
    static func record(_ snapshot: WalletSnapshot, network: String, alert: Bool) async {
        guard snapshot.synced else { return }
        let key = "notificationSeen.\(network)"
        let previous = UserDefaults.standard.stringArray(forKey: key)
        let oldIDs = Set(previous ?? [])
        let transactions = snapshot.transactions ?? []
        let sentIDs = Set(transactions.filter { $0.category == "send" }.map(\.txid))
        let incoming = Set(transactions
            .filter { ["receive", "generate", "immature"].contains($0.category) }
            .map(\.txid)).subtracting(sentIDs)
        let newIDs = incoming.subtracting(oldIDs)
        var remembered = previous ?? []
        remembered.append(contentsOf: newIDs.sorted())
        UserDefaults.standard.set(Array(remembered.suffix(200)), forKey: key)
        guard alert, previous != nil, !newIDs.isEmpty,
              UserDefaults.standard.bool(forKey: enabledKey) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Pearl 钱包收到新交易"
        content.body = "打开钱包查看收款和确认状态。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "pearl-receive-\(UUID().uuidString)",
                                            content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func runRefresh() async -> Bool {
        let network = UserDefaults.standard.string(forKey: "network") ?? "mainnet"
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return true }
        var completed = false
        do {
            try await WalletEngine.shared.startNotificationSync(network: network)
            for attempt in 0..<7 {
                try Task.checkCancellation()
                let snapshot = try await WalletEngine.shared.status()
                if snapshot.synced {
                    if LastSyncTime.isCurrent(snapshot) { LastSyncTime.record(network: network) }
                    await record(snapshot, network: network, alert: true)
                    completed = true
                    break
                }
                if attempt < 6 { try await Task.sleep(nanoseconds: 3_000_000_000) }
            }
        } catch { completed = false }
        await WalletEngine.shared.stopNotificationSync()
        return completed
    }
}
