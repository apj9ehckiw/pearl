import Foundation
import PearlCore

// The actor keeps blocking Go calls off the UI executor and serializes lifecycle work.
actor WalletEngine {
    static let shared = WalletEngine()

    func initialize(network: String) throws -> Bool {
        let root = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Pearl", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var resource = URLResourceValues()
        resource.isExcludedFromBackup = true
        var excluded = root
        try excluded.setResourceValues(resource)
        var exists = ObjCBool(false)
        var error: NSError?
        guard CoreInitialize(root.path, network, &exists, &error) else { throw failure(error) }
        return exists.boolValue
    }

    func mnemonic() throws -> String {
        var error: NSError?
        let result = CoreGenerateMnemonic(&error)
        if let error { throw error }
        return result
    }

    func create(phrase: String, password: String, restoring: Bool) throws {
        var error: NSError?
        let birthday: Int64 = restoring ? 0 : Int64(Date().timeIntervalSince1970) - 86_400
        guard CoreCreate(phrase, password, birthday, &error) else { throw failure(error) }
    }

    func open(password: String) throws {
        var error: NSError?
        guard CoreOpen(password, &error) else { throw failure(error) }
    }

    func checkPassword(_ password: String) throws {
        var error: NSError?
        guard CoreCheckPassword(password, &error) else { throw failure(error) }
    }

    func sync() throws {
        var error: NSError?
        guard CoreStartSync(&error) else { throw failure(error) }
    }

    func status() throws -> WalletSnapshot {
        var error: NSError?
        let json = CoreStatus(&error)
        if let error { throw error }
        return try JSONDecoder().decode(WalletSnapshot.self, from: Data(json.utf8))
    }

    func address() throws -> String {
        var error: NSError?
        let result = CoreReceiveAddress(&error)
        if let error { throw error }
        return result
    }

    func send(address: String, grains: Int64, fee: Int64, password: String) throws -> String {
        var error: NSError?
        let result = CoreSend(address, grains, fee, password, &error)
        if let error { throw error }
        return result
    }

    func close() throws {
        var error: NSError?
        guard CoreClose(&error) else { throw failure(error) }
    }

    private func failure(_ error: NSError?) -> Error {
        error ?? NSError(domain: "Pearl", code: 1, userInfo: [NSLocalizedDescriptionKey: "钱包操作失败"])
    }
}

struct WalletSnapshot: Decodable {
    var balance: Int64
    var pending: Int64
    var synced: Bool
    var height: Int
    var peerHeight: Int
    var transactions: [WalletTransaction]?
}

struct WalletTransaction: Decodable {
    let txid: String
    let category: String
    let amount: Decimal
    let confirmations: Int
    let time: Int
}

enum PearlAmount {
    static func grains(_ text: String) -> Int64? {
        // Deliberately reject exponent notation, signs and grouping separators.
        guard text.range(of: #"^[0-9]+(\.[0-9]{1,8})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              value > 0, value <= 21_000_000_000 else { return nil }
        return NSDecimalNumber(decimal: value * 100_000_000).int64Value
    }

    static func display(_ grains: Int64) -> String {
        NSDecimalNumber(decimal: Decimal(grains) / 100_000_000).stringValue
    }
}
