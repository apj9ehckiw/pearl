import SwiftUI

struct SendView: View {
    @EnvironmentObject private var wallet: WalletModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var address = ""
    @State private var amount = ""
    @State private var fee = "1000"
    @State private var password = ""
    @State private var confirming = false
    @State private var txid: String?
    private var grains: Int64? { PearlAmount.grains(amount) }
    private var validFee: Int64? {
        guard let value = Int64(fee), (1000...10000000).contains(value) else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                if let txid {
                    Section {
                        Label("Transaction broadcast", systemImage: "checkmark.circle.fill").foregroundStyle(.teal)
                        Text(txid).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                        Text("Wait for network confirmations in Activity.").foregroundStyle(.secondary)
                    }
                } else {
                    Section("Recipient") {
                        TextField("Pearl address", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Section("Amount") {
                        TextField("PRL", text: $amount).keyboardType(.decimalPad)
                        if let balance = wallet.snapshot?.balance { Text("Confirmed: \(PearlAmount.display(balance)) PRL").font(.caption) }
                    }
                    Section {
                        TextField("Grains per kB", text: $fee).keyboardType(.numberPad)
                    } header: { Text("Network fee rate · grains / kB") }
                    footer: { Text("1 PRL = 100,000,000 grains. The total fee depends on transaction size and is added to the amount. Minimum rate: 1,000 grains/kB.") }
                    Section("Authorize signing") {
                        SecureField("Wallet password", text: $password).textContentType(.password)
                        Text("Review the address, amount and fee rate before confirming.").font(.footnote)
                    }
                    Button("Review transfer") { confirming = true }
                        .disabled(grains == nil || validFee == nil || password.isEmpty || address.isEmpty || wallet.busy || wallet.snapshot?.synced != true)
                }
                if wallet.busy { ProgressView("Signing and broadcasting…") }
            }
            .disabled(wallet.busy)
            .navigationTitle("Send Pearl")
            .toolbar { Button("Done") { password = ""; dismiss() }.disabled(wallet.busy) }
            .interactiveDismissDisabled(wallet.busy)
            .confirmationDialog("Confirm transfer", isPresented: $confirming, titleVisibility: .visible) {
                Button("Send \(amount) PRL") {
                    guard let value = grains, let feeValue = validFee else { return }
                    let secret = password; password = ""
                    Task { txid = await wallet.send(address: address, amount: value, fee: feeValue, password: secret) }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Network: \(wallet.network)\nTo: \(address)\nAmount: \(amount) PRL\nFee rate: \(fee) grains/kB\nTransfers cannot be reversed.")
            }
            .onChange(of: phase) { value in if value == .background { password = ""; confirming = false } }
        }
    }
}
