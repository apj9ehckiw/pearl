import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var wallet: WalletModel
    @Environment(\.scenePhase) private var phase
    @State private var password = ""
    @State private var confirmation = ""
    @State private var phrase = ""
    @State private var verification = ""
    @State private var mode = "welcome"
    @State private var backedUp = false
    @State private var saveBiometric = false

    private var verified: Bool {
        let words = phrase.split(separator: " ")
        return words.count == 24 && verification.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
            == [String(words[2]), String(words[11]), String(words[23])]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    WalletEmblem().frame(width: 80, height: 80).padding(.top, 30)
                    Text(wallet.exists ? "欢迎回来" : "你的 Pearl，\n由你掌握")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                    Text(wallet.exists ? "解锁这台设备上的钱包。" : "独立钱包，私钥只保存在本机。")
                        .foregroundStyle(.secondary)
                    Picker("网络", selection: Binding(get: { wallet.network }, set: { value in
                        reset(); Task { await wallet.changeNetwork(value) }
                    })) {
                        Text("主网").tag("mainnet")
                        Text("测试网 2").tag("testnet2")
                    }.pickerStyle(.segmented).disabled(wallet.busy)

                    if wallet.exists {
                        if wallet.biometricEnabled, let name = wallet.biometricName {
                            action("使用\(name)解锁") { await wallet.unlockWithBiometrics() }
                        }
                        SecureField("钱包密码", text: $password).textContentType(.password).textFieldStyle(.roundedBorder)
                        if wallet.biometricName != nil && !wallet.biometricEnabled {
                            Toggle("下次使用生物识别解锁", isOn: $saveBiometric)
                        }
                        action("解锁钱包") {
                            let secret = password; password = ""
                            await wallet.open(password: secret)
                            if wallet.unlocked && saveBiometric {
                                _ = await wallet.enableBiometrics(password: secret)
                            }
                            saveBiometric = false
                        }.disabled(password.isEmpty || wallet.busy)
                    } else if mode == "welcome" {
                        action("创建钱包") {
                            do { phrase = try await WalletEngine.shared.mnemonic(); mode = "create" }
                            catch { wallet.error = "无法生成恢复短语，请重试。" }
                        }
                        Button("使用恢复短语导入") { mode = "restore" }.frame(maxWidth: .infinity)
                    } else {
                        if mode == "create" {
                            Text("抄写这 24 个单词").font(.title2.bold())
                            Text("按顺序离线保存。任何获得这些单词的人都能使用你的 Pearl；创建完成后不再显示。")
                                .font(.footnote).foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                                ForEach(Array(phrase.split(separator: " ").enumerated()), id: \.offset) { index, word in
                                    Text("\(index + 1). \(word)").font(.system(.callout, design: .monospaced))
                                }
                            }.padding().background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 16)).privacySensitive()
                            Toggle("我已离线备份恢复短语", isOn: $backedUp)
                            TextField("按顺序输入第 3、12、24 个单词，以空格分隔", text: $verification)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                        } else {
                            Text("恢复短语").font(.headline)
                            TextEditor(text: $phrase).frame(minHeight: 130).padding(8)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                                .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                            Text("支持未设置额外 BIP39 密语的 Oyster 助记词。恢复时会从创世区块开始扫描。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        SecureField("设置钱包密码（至少 10 个字符）", text: $password).textContentType(.newPassword).textFieldStyle(.roundedBorder)
                        SecureField("确认钱包密码", text: $confirmation).textContentType(.newPassword).textFieldStyle(.roundedBorder)
                        if wallet.biometricName != nil {
                            Toggle("以后使用生物识别解锁", isOn: $saveBiometric)
                        }
                        action(mode == "create" ? "创建钱包" : "导入钱包") {
                            let seed = phrase, secret = password, restoring = mode == "restore"
                            await wallet.open(password: secret, phrase: seed, restoring: restoring)
                            if wallet.unlocked && saveBiometric {
                                _ = await wallet.enableBiometrics(password: secret)
                            }
                            if wallet.exists { reset() }
                        }.disabled(wallet.busy || password.count < 10 || password != confirmation || phrase.isEmpty || (mode == "create" && (!backedUp || !verified)))
                        Button("返回") { reset() }.disabled(wallet.busy)
                    }
                    if wallet.busy { ProgressView("正在打开钱包…") }
                    Text("社区版本 · 基于 Pearl / Oyster").font(.caption).foregroundStyle(.secondary).padding(.top, 16)
                }.padding(26).disabled(!wallet.initialized)
            }.onChange(of: phase) { value in if value == .background { reset() } }
        }
    }

    private func action(_ title: String, perform: @escaping () async -> Void) -> some View {
        Button { Task { await perform() } } label: { Text(title).frame(maxWidth: .infinity).padding(10) }
            .buttonStyle(.borderedProminent).disabled(wallet.busy)
    }

    private func reset() {
        password = ""; confirmation = ""; phrase = ""; verification = ""; backedUp = false; saveBiometric = false; mode = "welcome"
    }
}

private struct WalletEmblem: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [.teal, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 74, height: 58).offset(y: 7)
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.30))
                .frame(width: 55, height: 12).offset(x: -5, y: -19)
            RoundedRectangle(cornerRadius: 10)
                .fill(.teal)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 2)
                .frame(width: 34, height: 28).offset(x: 24, y: 6)
            Circle().fill(.white).frame(width: 8, height: 8).offset(x: 25, y: 6)
        }
        .accessibilityLabel("钱包图标")
    }
}
