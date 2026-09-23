import Foundation

struct AddressBookEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var address: String

    init(id: UUID = UUID(), name: String = "", address: String = "") {
        self.id = id
        self.name = name
        self.address = address
    }
}

actor AddressBookStore {
    static let shared = AddressBookStore()

    func load(network: String) throws -> [AddressBookEntry] {
        let url = try fileURL(network: network)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([AddressBookEntry].self, from: Data(contentsOf: url))
    }

    func save(_ entries: [AddressBookEntry], network: String) throws {
        let url = try fileURL(network: network)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func fileURL(network: String) throws -> URL {
        guard network == "mainnet" || network == "testnet2" else {
            throw NSError(domain: "Pearl", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "不支持的网络"])
        }
        let root = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Pearl", isDirectory: true)
        let directory = root.appendingPathComponent(network, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        return directory.appendingPathComponent("address-book.json")
    }
}
