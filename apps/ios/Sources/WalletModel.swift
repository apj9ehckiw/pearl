import SwiftUI

@MainActor
final class WalletModel: ObservableObject {
    @Published var exists = false
    @Published var unlocked = false
    @Published var busy = false
    @Published var initialized = false
    @Published var error: String?
    @Published var snapshot: WalletSnapshot?
    @Published var syncRemaining: TimeInterval?
    @Published var lastSyncedAt: Date?
    @Published var receiveAddress = ""
    @Published var network = UserDefaults.standard.string(forKey: "network") ?? "mainnet"
    @Published var syncPeer = ""
    @Published var biometricName: String?
    @Published var biometricEnabled = false
    private var generation = 0
    private var backgroundEnteredAt: Date?
    private var syncEstimator = SyncEstimator()
    private let engine = WalletEngine.shared

    func initialize() async {
        initialized = false
        syncPeer = UserDefaults.standard.string(forKey: "syncPeer.\(network)") ?? ""
        lastSyncedAt = LastSyncTime.load(network: network)
        biometricName = BiometricStore.availableName()
        biometricEnabled = UserDefaults.standard.bool(forKey: biometricKey)
        do { exists = try await engine.initialize(network: network); initialized = true }
        catch { self.error = message(error) }
    }

    func changeNetwork(_ value: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        await lock()
        network = value
        UserDefaults.standard.set(value, forKey: "network")
        await initialize()
    }

    func open(password: String, phrase: String? = nil, restoring: Bool = false) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let request = generation
        do {
            if let phrase {
                try await engine.create(phrase: phrase, password: password, restoring: restoring)
                exists = true
            } else { try await engine.open(password: password) }
            try await finishOpening(request: request)
        } catch { self.error = message(error) }
    }

    func unlockWithBiometrics() async {
        guard exists, biometricEnabled, biometricName != nil, !busy else { return }
        busy = true
        defer { busy = false }
        let request = generation
        let selectedNetwork = network
        do {
            let password = try await BiometricStore.shared.read(network: selectedNetwork,
                reason: "使用生物识别解锁 Pearl 钱包")
            guard request == generation, selectedNetwork == network else { return }
            try await engine.open(password: password)
            try await finishOpening(request: request)
        } catch BiometricStoreError.cancelled {
            // A cancelled system prompt leaves the manual password path available.
        } catch {
            self.error = message(error)
        }
    }

    func enableBiometrics(password: String) async -> Bool {
        guard unlocked, !busy, biometricName != nil else { return false }
        busy = true
        defer { busy = false }
        let selectedNetwork = network
        let request = generation
        do {
            try await engine.checkPassword(password)
            guard request == generation, unlocked, selectedNetwork == network else { return false }
            try await BiometricStore.shared.save(password, network: selectedNetwork)
            guard request == generation, unlocked, selectedNetwork == network else {
                await BiometricStore.shared.remove(network: selectedNetwork)
                return false
            }
            UserDefaults.standard.set(true, forKey: biometricKey)
            biometricEnabled = true
            return true
        } catch {
            self.error = message(error)
            return false
        }
    }

    func disableBiometrics() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        await BiometricStore.shared.remove(network: network)
        UserDefaults.standard.set(false, forKey: biometricKey)
        biometricEnabled = false
    }

    private var biometricKey: String { "biometric-unlock.\(network)" }

    private func finishOpening(request: Int) async throws {
        guard request == generation else { try await engine.close(); return }
        unlocked = true
        try await engine.sync()
        guard request == generation else { return }
        let address = try await engine.address()
        guard request == generation else { return }
        receiveAddress = address
        let result = try await engine.status()
        if request == generation { await accept(result) }
    }

    func refresh() async {
        guard unlocked, !busy else { return }
        let request = generation
        do {
            let result = try await engine.status()
            if request == generation { await accept(result) }
        } catch { if request == generation { self.error = message(error) } }
    }

    func retrySync() async {
        guard !busy else { return }
        busy = true
        let request = generation
        defer { busy = false }
        do {
            try await engine.sync()
            let address = try await engine.address()
            if request == generation { receiveAddress = address }
        } catch { self.error = message(error) }
    }

    func lock() async {
        generation += 1
        unlocked = false
        snapshot = nil
        syncRemaining = nil
        syncEstimator = SyncEstimator()
        receiveAddress = ""
        backgroundEnteredAt = nil
        do { try await engine.close() }
        catch { self.error = message(error) }
    }

    func enteredBackground(at date: Date = Date()) {
        backgroundEnteredAt = date
    }

    func lockAfterBackground(immediately: Bool, now: Date = Date()) async {
        guard let enteredAt = backgroundEnteredAt else { return }
        backgroundEnteredAt = nil
        let configured = UserDefaults.standard.integer(forKey: "autoLockMinutes")
        if immediately || AutoLockPolicy.shouldLock(backgroundEnteredAt: enteredAt,
            now: now, configuredMinutes: configured) {
            await lock()
        }
    }

    func configureSyncPeer(_ address: String) async {
        guard unlocked, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let normalized = try await engine.normalizeSyncPeer(address)
            guard normalized != syncPeer else { return }
            UserDefaults.standard.set(normalized, forKey: "syncPeer.\(network)")
            syncPeer = normalized
            await lock()
        } catch {
            self.error = "节点地址无效。请输入主机名或 IP，可附加端口；不要输入 HTTP URL。"
        }
    }

    func send(address: String, amount: Int64, fee: Int64, password: String) async -> String? {
        guard unlocked, !busy else { return nil }
        busy = true
        defer { busy = false }
        do {
            let txid = try await engine.send(address: address, grains: amount, fee: fee, password: password)
            return txid
        }
        catch { self.error = "\(message(error))\n重试前请先查看交易记录；交易可能已经广播。"; return nil }
    }

    func sendWithBiometrics(address: String, amount: Int64, fee: Int64) async -> String? {
        guard unlocked, biometricEnabled, biometricName != nil, !busy else { return nil }
        busy = true
        defer { busy = false }
        let request = generation
        let selectedNetwork = network
        do {
            let password = try await BiometricStore.shared.read(network: selectedNetwork,
                reason: "验证并发送 \(PearlAmount.display(amount)) PRL")
            guard request == generation, unlocked, selectedNetwork == network else { return nil }
            let txid = try await engine.send(address: address, grains: amount, fee: fee, password: password)
            return txid
        } catch BiometricStoreError.cancelled {
            return nil
        } catch {
            self.error = "\(message(error))\n重试前请先查看交易记录；交易可能已经广播。"
            return nil
        }
    }

    func exportSecret(kind: WalletExportKind, password: String) async -> WalletSecret? {
        guard unlocked, !busy, !password.isEmpty else { return nil }
        busy = true
        defer { busy = false }
        let request = generation
        do {
            let secret: WalletSecret
            switch kind {
            case .mnemonic:
                secret = WalletSecret(value: try await engine.exportMnemonic(password: password), address: nil)
            case .privateKey:
                let key = try await engine.exportPrivateKey(password: password)
                secret = WalletSecret(value: key.wif, address: key.address)
            }
            guard request == generation, unlocked else { return nil }
            return secret
        } catch {
            self.error = message(error)
            return nil
        }
    }

    func validateAddress(_ address: String) async -> Bool {
        guard unlocked else { return false }
        return await engine.validateAddress(address)
    }

    private func accept(_ result: WalletSnapshot) async {
        snapshot = result
        lastSyncedAt = LastSyncTime.load(network: network)
        if LastSyncTime.isCurrent(result) {
            lastSyncedAt = LastSyncTime.record(network: network)
        }
        syncRemaining = syncEstimator.update(walletHeight: result.walletHeight,
                                             peerHeight: result.peerHeight,
                                             synced: result.synced)
        await BackgroundNotifications.record(result, network: network,
                                             alert: UIApplication.shared.applicationState == .background)
    }

    private func message(_ error: Error) -> String {
        if let error = error as? BiometricStoreError { return error.localizedDescription }
        let detail = error.localizedDescription
        let lower = detail.lowercased()
        if lower.contains("invalid passphrase") || lower.contains("wrong passphrase") || lower.contains("invalid password") {
            return "钱包密码错误。"
        }
        if lower.contains("invalid bip39") { return "恢复短语无效，请检查 24 个英文单词及顺序。" }
        if lower.contains("insufficient") { return "余额不足，或余额不足以支付手续费。" }
        if lower.contains("invalid address") { return "地址无效，或与当前网络不匹配。" }
        if lower.contains("invalid amount") { return "发送金额无效。" }
        if lower.contains("fee must") { return "手续费率超出允许范围。" }
        if lower.contains("wallet is closed") { return "钱包已锁定，请重新解锁。" }
        if lower.contains("wallet already open") { return "钱包已经打开。" }
        if lower.contains("recovery phrase unavailable") { return "此钱包创建时未保存原助记词，无法从现有密钥还原。请使用创建时离线备份的 24 个词。" }
        if lower.contains("recovery phrase vault") { return "恢复短语加密文件无法读取，请使用离线备份恢复。" }
        if lower.contains("at least 10 characters") { return "钱包密码至少需要 10 个字符。" }
        if lower.contains("wallet synchronization") { return "请等待钱包同步完成。" }
        return "操作失败，请检查网络连接或稍后重试。"
    }
}

enum LastSyncTime {
    private static func key(_ network: String) -> String { "lastSyncedAt.\(network)" }

    static func load(network: String) -> Date? {
        UserDefaults.standard.object(forKey: key(network)) as? Date
    }

    static func isCurrent(_ snapshot: WalletSnapshot) -> Bool {
        snapshot.synced && snapshot.peerHeight > 0 &&
            snapshot.height >= snapshot.peerHeight && snapshot.walletHeight >= snapshot.peerHeight
    }

    @discardableResult
    static func record(network: String, at date: Date = Date()) -> Date {
        if let previous = load(network: network) {
            let elapsed = date.timeIntervalSince(previous)
            if elapsed >= 0 && elapsed < 60 { return previous }
        }
        UserDefaults.standard.set(date, forKey: key(network))
        return date
    }
}

enum WalletExportKind: String, CaseIterable, Identifiable {
    case mnemonic = "助记词"
    case privateKey = "当前地址私钥"
    var id: String { rawValue }
}

struct WalletSecret {
    let value: String
    let address: String?
}

enum AutoLockPolicy {
    static func shouldLock(backgroundEnteredAt: Date, now: Date, configuredMinutes: Int) -> Bool {
        let minutes = configuredMinutes > 0 ? min(configuredMinutes, 60) : 5
        return now.timeIntervalSince(backgroundEnteredAt) >= TimeInterval(minutes * 60)
    }
}
