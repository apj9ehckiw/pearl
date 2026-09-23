import SwiftUI

struct SendView: View {
    @EnvironmentObject private var wallet: WalletModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var address = ""
    @State private var amount = ""
    @State private var fee = "1000"
    @State private var password = ""
    @State private var authorization = "password"
    @State private var confirming = false
    @State private var txid: String?
    private var grains: Int64? { PearlAmount.grains(amount) }
    private var validFee: Int64? {
        guard let value = Int64(fee), (1000...10000000).contains(value) else { return nil }
        return value
    }
    private var biometricAuthorization: Bool {
        authorization == "biometric" && wallet.biometricEnabled && wallet.biometricName != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if let txid {
                    Section {
                        Label("交易已广播", systemImage: "checkmark.circle.fill").foregroundStyle(.teal)
                        Text(txid).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                        Text("请在交易记录中查看网络确认进度。").foregroundStyle(.secondary)
                    }
                } else {
                    Section("收款方") {
                        TextField("Pearl 地址", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Section("金额") {
                        TextField("PRL", text: $amount).keyboardType(.decimalPad)
                        if let balance = wallet.snapshot?.balance { Text("已确认余额：\(PearlAmount.display(balance)) PRL").font(.caption) }
                    }
                    Section {
                        TextField("每 kB 的最小单位数", text: $fee).keyboardType(.numberPad)
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
                        } else {
                            Label("确认转账后验证生物识别", systemImage: "checkmark.shield")
                                .foregroundStyle(.secondary)
                        }
                        Text("确认前请核对地址、金额和费率。").font(.footnote)
                    }
                    Button("核对转账") { confirming = true }
                        .disabled(grains == nil || validFee == nil ||
                            (!biometricAuthorization && password.isEmpty) ||
                            address.isEmpty || wallet.busy || wallet.snapshot?.synced != true)
                }
                if wallet.busy { ProgressView("正在签名并广播…") }
            }
            .disabled(wallet.busy)
            .navigationTitle("发送 Pearl")
            .toolbar { Button("完成") { password = ""; dismiss() }.disabled(wallet.busy) }
            .interactiveDismissDisabled(wallet.busy)
            .confirmationDialog("确认转账", isPresented: $confirming, titleVisibility: .visible) {
                Button("发送 \(amount) PRL") {
                    guard let value = grains, let feeValue = validFee else { return }
                    let secret = password; password = ""
                    let useBiometrics = biometricAuthorization
                    Task {
                        if useBiometrics {
                            txid = await wallet.sendWithBiometrics(address: address, amount: value, fee: feeValue)
                        } else {
                            txid = await wallet.send(address: address, amount: value, fee: feeValue, password: secret)
                        }
                    }
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("网络：\(wallet.network == "mainnet" ? "主网" : "测试网")\n收款地址：\(address)\n金额：\(amount) PRL\n费率：\(fee) grains/kB\n转账一经发送无法撤销。")
            }
            .onChange(of: phase) { value in if value == .background { password = ""; confirming = false } }
            .onChange(of: authorization) { value in if value == "biometric" { password = "" } }
            .onChange(of: wallet.biometricEnabled) { value in if !value { authorization = "password" } }
            .onAppear { if wallet.biometricEnabled && wallet.biometricName != nil { authorization = "biometric" } }
        }
    }
}
