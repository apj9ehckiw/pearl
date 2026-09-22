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
    private var generation = 0
    private let engine = WalletEngine.shared

    func initialize() async {
        initialized = false
        do { exists = try await engine.initialize(network: network); initialized = true }
        catch { self.error = error.localizedDescription }
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
            guard request == generation else { try await engine.close(); return }
            unlocked = true
            try await engine.sync()
            guard request == generation else { return }
            let address = try await engine.address()
            guard request == generation else { return }
            receiveAddress = address
            let result = try await engine.status()
            if request == generation { snapshot = result }
        } catch { self.error = error.localizedDescription }
    }

    func refresh() async {
        guard unlocked, !busy else { return }
        let request = generation
        do {
            let result = try await engine.status()
            if request == generation { snapshot = result }
        } catch { if request == generation { self.error = error.localizedDescription } }
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
        } catch { self.error = error.localizedDescription }
    }

    func lock() async {
        generation += 1
        unlocked = false
        snapshot = nil
        receiveAddress = ""
        do { try await engine.close() }
        catch { self.error = error.localizedDescription }
    }

    func send(address: String, amount: Int64, fee: Int64, password: String) async -> String? {
        guard unlocked, !busy else { return nil }
        busy = true
        defer { busy = false }
        do { return try await engine.send(address: address, grains: amount, fee: fee, password: password) }
        catch { self.error = "\(error.localizedDescription)\nCheck Activity before retrying; a broadcast may already have reached peers."; return nil }
    }
}
