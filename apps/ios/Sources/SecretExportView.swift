import SwiftUI
import UniformTypeIdentifiers

struct SecretExportView: View {
    @EnvironmentObject private var wallet: WalletModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @State private var kind: WalletExportKind = .mnemonic
    @State private var password = ""
    @State private var secret: WalletSecret?
    @State private var revealID = UUID()

    var body: some View {
        NavigationStack {
            Form {
                Section("选择导出内容") {
                    Picker("类型", selection: $kind) {
                        ForEach(WalletExportKind.allCases) { choice in
                            Text(choice.rawValue).tag(choice)
                        }
                    }
                    .onChange(of: kind) { _ in hide() }
                    Text(kind == .mnemonic
                         ? "24 个单词可恢复整个钱包。请离线保存，勿发送给任何人。"
                         : "仅导出当前收款地址的 BIP86 Taproot 原始私钥（WIF）。导入其他钱包时需支持相同的 Taproot 密钥派生规则；它不能代替助记词恢复整个钱包。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let secret {
                    Section(kind.rawValue) {
                        if let address = secret.address {
                            Text("对应地址").font(.caption).foregroundStyle(.secondary)
                            Text(address).font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        if kind == .mnemonic {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                                      alignment: .leading, spacing: 12) {
                                ForEach(Array(secret.value.split(separator: " ").enumerated()), id: \.offset) { index, word in
                                    Text("\(index + 1). \(word)")
                                        .font(.system(.callout, design: .monospaced))
                                }
                            }.padding(.vertical, 8).privacySensitive()
                        } else {
                            Text(secret.value).font(.system(.body, design: .monospaced))
                                .privacySensitive()
                        }
                        Button("复制到本机剪贴板（1 分钟后过期）") {
                            UIPasteboard.general.setItems(
                                [[UTType.utf8PlainText.identifier: secret.value]],
                                options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
                        }
                        Button("立即隐藏") { hide() }
                    }
                    Section {
                        Text("敏感内容将在 1 分钟后自动隐藏。截屏或其他应用读取剪贴板仍可能泄露密钥。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Section("验证钱包密码") {
                        SecureField("输入钱包密码", text: $password)
                            .textContentType(.password)
                        Button("校验并显示") {
                            let input = password
                            password = ""
                            let id = UUID()
                            revealID = id
                            Task {
                                if let result = await wallet.exportSecret(kind: kind, password: input),
                                   revealID == id, phase == .active, wallet.unlocked {
                                    secret = result
                                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                                    if revealID == id { hide() }
                                }
                            }
                        }.disabled(password.isEmpty || wallet.busy)
                    }
                }
            }
            .navigationTitle("导出密钥")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { hide(); dismiss() } } }
        }
        .onChange(of: phase) { value in if value != .active { hide() } }
        .onChange(of: wallet.unlocked) { value in if !value { hide(); dismiss() } }
        .onDisappear { hide() }
    }

    private func hide() {
        password = ""
        secret = nil
        revealID = UUID()
    }
}
