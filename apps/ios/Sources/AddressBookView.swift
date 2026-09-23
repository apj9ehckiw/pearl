import SwiftUI

struct AddressBookView: View {
    @EnvironmentObject private var wallet: WalletModel
    @State private var entries: [AddressBookEntry] = []
    @State private var editing: AddressBookEntry?
    @State private var recipient: AddressBookEntry?

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("地址簿为空").font(.headline)
                        Text("保存常用收款地址，下次转账时可直接选择。")
                            .foregroundStyle(.secondary)
                    }.padding(.vertical, 20)
                }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.name).font(.headline)
                        Text(entry.address).font(.system(.caption, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        HStack {
                            Button("转账") { recipient = entry }
                            Spacer()
                            Button("编辑") { editing = entry }
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 5)
                }.onDelete { offsets in
                    Task { await remove(at: offsets) }
                }
            }
            .navigationTitle("地址簿")
            .toolbar { Button { editing = AddressBookEntry() } label: { Image(systemName: "plus") } }
            .task(id: wallet.network) { await reload() }
            .sheet(item: $editing) { entry in
                AddressBookEditorView(entry: entry) { updated in await save(updated) }
                    .environmentObject(wallet)
            }
            .sheet(item: $recipient) { entry in
                SendView(initialAddress: entry.address).environmentObject(wallet)
            }
        }
    }

    private func reload() async {
        do { entries = try await AddressBookStore.shared.load(network: wallet.network) }
        catch { wallet.error = "无法读取地址簿，请稍后重试。" }
    }

    private func save(_ entry: AddressBookEntry) async -> Bool {
        if entries.contains(where: { $0.id != entry.id && $0.address == entry.address }) {
            wallet.error = "此地址已保存在地址簿中。"
            return false
        }
        var updated = entries
        if let index = updated.firstIndex(where: { $0.id == entry.id }) { updated[index] = entry }
        else { updated.append(entry) }
        updated.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        do {
            try await AddressBookStore.shared.save(updated, network: wallet.network)
            entries = updated
            return true
        } catch {
            wallet.error = "无法保存地址簿，请检查设备存储空间。"
            return false
        }
    }

    private func remove(at offsets: IndexSet) async {
        var updated = entries
        updated.remove(atOffsets: offsets)
        do {
            try await AddressBookStore.shared.save(updated, network: wallet.network)
            entries = updated
        } catch { wallet.error = "无法删除地址，请稍后重试。" }
    }
}

private struct AddressBookEditorView: View {
    @EnvironmentObject private var wallet: WalletModel
    @Environment(\.dismiss) private var dismiss
    let entry: AddressBookEntry
    let onSave: (AddressBookEntry) async -> Bool
    @State private var name: String
    @State private var address: String
    @State private var saving = false

    init(entry: AddressBookEntry, onSave: @escaping (AddressBookEntry) async -> Bool) {
        self.entry = entry
        self.onSave = onSave
        _name = State(initialValue: entry.name)
        _address = State(initialValue: entry.address)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("联系人") {
                    TextField("名称", text: $name)
                    TextField("Pearl 地址", text: $address)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {
                    Text("地址会按当前\(wallet.network == "mainnet" ? "主网" : "测试网")校验，并仅保存在这台设备上。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(entry.name.isEmpty ? "添加地址" : "编辑地址")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        saving = true
                        Task {
                            let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            let cleanedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard await wallet.validateAddress(cleanedAddress) else {
                                wallet.error = "地址无效，或与当前网络不匹配。"
                                saving = false
                                return
                            }
                            let updated = AddressBookEntry(id: entry.id, name: cleanedName, address: cleanedAddress)
                            if await onSave(updated) { dismiss() }
                            saving = false
                        }
                    }.disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                               name.count > 50 || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct AddressBookPickerView: View {
    @EnvironmentObject private var wallet: WalletModel
    @Environment(\.dismiss) private var dismiss
    let onSelect: (AddressBookEntry) -> Void
    @State private var entries: [AddressBookEntry] = []

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty { Text("地址簿为空，请先在地址簿页面添加收款地址。") }
                ForEach(entries) { entry in
                    Button {
                        onSelect(entry)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.name).font(.headline)
                            Text(entry.address).font(.system(.caption, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
            .navigationTitle("选择收款方")
            .toolbar { Button("取消") { dismiss() } }
            .task {
                do { entries = try await AddressBookStore.shared.load(network: wallet.network) }
                catch { wallet.error = "无法读取地址簿，请稍后重试。" }
            }
        }
    }
}
