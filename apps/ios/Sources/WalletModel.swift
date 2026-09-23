import SwiftUI

@MainActor
final class WalletModel: ObservableObject {
    @Published var exists = false
    @Published var unlocked = false
    @Published var busy = false
    @Published var initialized = false
    @Published var error: String?
    @Published var snapshot: WalletSnapshot?
    @Published var receiveAddress = ""
    @Published var network = UserDefaults.standard.string(forKey: "network") ?? "mainnet"
    @Published var biometricName: String?
    @Published var biometricEnabled = false
    private var generation = 0
    private var lastActivity = Date()
    private let engine = WalletEngine.shared

    func initialize() async {
        initialized = false
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
        noteActivity()
        try await engine.sync()
        guard request == generation else { return }
        let address = try await engine.address()
        guard request == generation else { return }
        receiveAddress = address
        let result = try await engine.status()
        if request == generation { snapshot = result }
    }

    func refresh() async {
        guard unlocked, !busy else { return }
        let request = generation
        do {
            let result = try await engine.status()
            if request == generation { snapshot = result }
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
        receiveAddress = ""
        do { try await engine.close() }
        catch { self.error = message(error) }
    }

    func noteActivity() {
        lastActivity = Date()
    }

    func lockIfExpired() async {
        guard unlocked, !busy else { return }
        let configured = UserDefaults.standard.integer(forKey: "autoLockMinutes")
        if AutoLockPolicy.shouldLock(since: lastActivity, now: Date(), configuredMinutes: configured) {
            await lock()
        }
    }

    func send(address: String, amount: Int64, fee: Int64, password: String) async -> String? {
        guard unlocked, !busy else { return nil }
        busy = true
        defer { busy = false }
        noteActivity()
        do {
            let txid = try await engine.send(address: address, grains: amount, fee: fee, password: password)
            noteActivity()
            return txid
        }
        catch { self.error = "\(message(error))\n重试前请先查看交易记录；交易可能已经广播。"; return nil }
    }

    func sendWithBiometrics(address: String, amount: Int64, fee: Int64) async -> String? {
        guard unlocked, biometricEnabled, biometricName != nil, !busy else { return nil }
        busy = true
        defer { busy = false }
        noteActivity()
        let request = generation
        let selectedNetwork = network
        do {
            let password = try await BiometricStore.shared.read(network: selectedNetwork,
                reason: "验证并发送 \(PearlAmount.display(amount)) PRL")
            guard request == generation, unlocked, selectedNetwork == network else { return nil }
            if AutoLockPolicy.shouldLock(since: lastActivity, now: Date(),
                configuredMinutes: UserDefaults.standard.integer(forKey: "autoLockMinutes")) {
                self.error = "闲置时间已到，钱包已锁定。请重新解锁后重试转账。"
                await lock()
                return nil
            }
            let txid = try await engine.send(address: address, grains: amount, fee: fee, password: password)
            noteActivity()
            return txid
        } catch BiometricStoreError.cancelled {
            return nil
        } catch {
            self.error = "\(message(error))\n重试前请先查看交易记录；交易可能已经广播。"
            return nil
        }
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
        if lower.contains("at least 10 characters") { return "钱包密码至少需要 10 个字符。" }
        if lower.contains("wallet synchronization") { return "请等待钱包同步完成。" }
        return "操作失败，请检查网络连接或稍后重试。"
    }
}

enum AutoLockPolicy {
    static func shouldLock(since lastActivity: Date, now: Date, configuredMinutes: Int) -> Bool {
        let minutes = configuredMinutes > 0 ? min(configuredMinutes, 60) : 5
        return now.timeIntervalSince(lastActivity) >= TimeInterval(minutes * 60)
    }
}
