import SwiftUI

struct SendView: View {
    @EnvironmentObject private var wallet: WalletModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var address: String
    @State private var showAddressBook = false
    @State private var amount = ""
    @State private var sendAll = false
    @State private var useFixedChange = false
    @State private var changeAddress = ""
    @State private var sweepPreview: SweepPreview?
    @State private var fee = "1000"
    @State private var password = ""
    @State private var authorization = "password"
    @State private var confirming = false
    @State private var txid: String?
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case address, amount, fee, changeAddress, password }
    private var grains: Int64? { PearlAmount.grains(amount) }
    private var validFee: Int64? {
        guard let value = Int64(fee), (1000...10000000).contains(value) else { return nil }
        return value
    }
    private var biometricAuthorization: Bool {
        authorization == "biometric" && wallet.biometricEnabled && wallet.biometricName != nil
    }

    init(initialAddress: String = "") {
        _address = State(initialValue: initialAddress)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let txid {
                    Section {
                        Label("交易已广播", systemImage: "checkmark.circle.fill").foregroundStyle(PearlTheme.accent)
                        Text(txid).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                        Text("请在交易记录中查看网络确认进度。").foregroundStyle(.secondary)
                    }
                } else {
                    Section("收款方") {
                        TextField("Pearl 地址", text: $address)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focusedField, equals: .address)
                        Button("从地址簿选择") { showAddressBook = true }
                    }
                    Section("金额") {
                        Toggle("发送全部（不生成找零）", isOn: $sendAll)
                        if !sendAll {
                            TextField("PRL", text: $amount).keyboardType(.decimalPad)
                                .focused($focusedField, equals: .amount)
                        } else {
                            Text("将全部已确认、可花费的余额发送到收款地址；确认前会显示扣除手续费后的准确金额。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if let balance = wallet.snapshot?.balance { Text("已确认余额：\(PearlAmount.display(balance)) PRL").font(.caption) }
                    }
                    if !sendAll {
                        Section {
                            Toggle("找零退回网页钱包旧地址", isOn: $useFixedChange)
                            if useFixedChange {
                                TextField("网页钱包已识别的旧地址", text: $changeAddress)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .focused($focusedField, equals: .changeAddress)
                            }
                        } header: { Text("网页钱包兼容") }
                        footer: {
                            Text("仅填写属于此钱包、且网页端已经识别的地址。钱包会验证归属；复用地址会降低隐私。留空则使用新的派生找零地址。")
                        }
                    }
                    Section {
                        TextField("每 kB 的最小单位数", text: $fee).keyboardType(.numberPad)
                            .focused($focusedField, equals: .fee)
                    } header: { Text("网络费率 · grains / kB") }
                    footer: { Text("1 PRL = 100,000,000 grains。实际手续费随交易大小变化，会在发送金额之外扣除。最低费率为 1,000 grains/kB。") }
                    Section("授权签名") {
                        if wallet.biometricEnabled, let name = wallet.biometricName {
                            Picker("验证方式", selection: $authorization) {
                                Text(name).tag("biometric")
                                Text("钱包密码").tag("password")
                            }.pickerStyle(.segmented)
                        }
                        if !biometricAuthorization {
                            SecureField("钱包密码", text: $password).textContentType(.password)
                                .focused($focusedField, equals: .password)
                        } else {
                            Label("确认转账后验证生物识别", systemImage: "checkmark.shield")
                                .foregroundStyle(.secondary)
                        }
                        Text("确认前请核对地址、金额和费率。").font(.footnote)
                    }
                    Button(sendAll ? "核对发送全部" : "核对转账") {
                        focusedField = nil
                        guard let feeValue = validFee else { return }
                        if sendAll {
                            Task {
                                sweepPreview = await wallet.previewSweep(address: address, fee: feeValue)
                                confirming = sweepPreview != nil
                            }
                        } else {
                            sweepPreview = nil
                            confirming = true
                        }
                    }
                        .disabled((!sendAll && grains == nil) || validFee == nil ||
                            (!biometricAuthorization && password.isEmpty) ||
                            address.isEmpty || (!sendAll && useFixedChange && changeAddress.isEmpty) ||
                            wallet.busy || wallet.snapshot?.synced != true)
                }
                if wallet.busy { ProgressView("正在签名并广播…") }
            }
            .disabled(wallet.busy)
            .navigationTitle("发送 Pearl")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { password = ""; dismiss() }.disabled(wallet.busy)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { focusedField = nil }
                }
            }
            .interactiveDismissDisabled(wallet.busy)
            .sheet(isPresented: $showAddressBook) {
                AddressBookPickerView { entry in address = entry.address }
                    .environmentObject(wallet)
            }
            .confirmationDialog("确认转账", isPresented: $confirming, titleVisibility: .visible) {
                Button("发送 \(sendAll ? PearlAmount.display(sweepPreview?.amount ?? 0) : amount) PRL") {
                    guard let feeValue = validFee else { return }
                    let secret = password; password = ""
                    let useBiometrics = biometricAuthorization
                    let recipient = address
                    let sweepMode = sendAll
                    let selectedChange = useFixedChange && !sendAll ? changeAddress : ""
                    let preview = sweepPreview
                    Task {
                        if sweepMode {
                            guard let preview else { return }
                            if useBiometrics {
                                txid = await wallet.sweepWithBiometrics(address: recipient, fee: feeValue, preview: preview)
                            } else {
                                txid = await wallet.sweep(address: recipient, fee: feeValue, preview: preview, password: secret)
                            }
                        } else if let value = grains {
                            if useBiometrics {
                                txid = await wallet.sendWithBiometrics(address: recipient, amount: value,
                                    fee: feeValue, changeAddress: selectedChange)
                            } else {
                                txid = await wallet.send(address: recipient, amount: value,
                                    fee: feeValue, changeAddress: selectedChange, password: secret)
                            }
                        }
                    }
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text(sendAll
                    ? "网络：\(wallet.network == "mainnet" ? "主网" : "测试网")\n收款地址：\(address)\n发送金额：\(PearlAmount.display(sweepPreview?.amount ?? 0)) PRL\n预计手续费：\(PearlAmount.display(sweepPreview?.fee ?? 0)) PRL\n输入数：\(sweepPreview?.inputs ?? 0)\n不会产生找零。转账无法撤销。"
                    : "网络：\(wallet.network == "mainnet" ? "主网" : "测试网")\n收款地址：\(address)\n金额：\(amount) PRL\n找零地址：\(useFixedChange ? changeAddress : "新派生地址")\n费率：\(fee) grains/kB\n转账一经发送无法撤销。")
            }
            .onChange(of: phase) { value in if value == .background { password = ""; confirming = false } }
            .onChange(of: authorization) { value in if value == "biometric" { password = "" } }
            .onChange(of: wallet.biometricEnabled) { value in if !value { authorization = "password" } }
            .onAppear {
                if wallet.biometricEnabled && wallet.biometricName != nil { authorization = "biometric" }
                changeAddress = wallet.compatibleChangeAddress
                useFixedChange = !changeAddress.isEmpty
            }
        }
    }
}
