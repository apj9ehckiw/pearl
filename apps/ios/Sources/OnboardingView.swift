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

    private var verified: Bool {
        let words = phrase.split(separator: " ")
        return words.count == 24 && verification.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
            == [String(words[2]), String(words[11]), String(words[23])]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "circle.hexagongrid.fill").font(.system(size: 64)).foregroundStyle(.teal).padding(.top, 30)
                    Text(wallet.exists ? "Welcome back." : "A home for\nyour Pearl.")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                    Text(wallet.exists ? "Unlock the wallet on this device." : "An independent wallet. Private keys stay with you.")
                        .foregroundStyle(.secondary)
                    Picker("Network", selection: Binding(get: { wallet.network }, set: { value in
                        reset(); Task { await wallet.changeNetwork(value) }
                    })) {
                        Text("Mainnet").tag("mainnet")
                        Text("Testnet 2").tag("testnet2")
                    }.pickerStyle(.segmented).disabled(wallet.busy)

                    if wallet.exists {
                        SecureField("Wallet password", text: $password).textContentType(.password).textFieldStyle(.roundedBorder)
                        action("Unlock wallet") {
                            let secret = password; password = ""
                            await wallet.open(password: secret)
                        }.disabled(password.isEmpty || wallet.busy)
                    } else if mode == "welcome" {
                        action("Create a wallet") {
                            do { phrase = try await WalletEngine.shared.mnemonic(); mode = "create" }
                            catch { wallet.error = error.localizedDescription }
                        }
                        Button("Restore with recovery phrase") { mode = "restore" }.frame(maxWidth: .infinity)
                    } else {
                        if mode == "create" {
                            Text("Write down your 24 words").font(.title2.bold())
                            Text("Keep these offline and in order. Anyone with these words can spend your Pearl. They will only be shown during setup.")
                                .font(.footnote).foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                                ForEach(Array(phrase.split(separator: " ").enumerated()), id: \.offset) { index, word in
                                    Text("\(index + 1). \(word)").font(.system(.callout, design: .monospaced))
                                }
                            }.padding().background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 16)).privacySensitive()
                            Toggle("I saved my recovery phrase offline", isOn: $backedUp)
                            TextField("Enter words 3, 12 and 24, separated by spaces", text: $verification)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                        } else {
                            Text("Recovery phrase").font(.headline)
                            TextEditor(text: $phrase).frame(minHeight: 130).padding(8)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                                .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                            Text("Supports Oyster BIP39 phrases without an additional BIP39 passphrase. Recovery scans from genesis.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        SecureField("New password (10+ characters)", text: $password).textContentType(.newPassword).textFieldStyle(.roundedBorder)
                        SecureField("Confirm password", text: $confirmation).textContentType(.newPassword).textFieldStyle(.roundedBorder)
                        action(mode == "create" ? "Create wallet" : "Restore wallet") {
                            let seed = phrase, secret = password, restoring = mode == "restore"
                            await wallet.open(password: secret, phrase: seed, restoring: restoring)
                            if wallet.exists { reset() }
                        }.disabled(wallet.busy || password.count < 10 || password != confirmation || phrase.isEmpty || (mode == "create" && (!backedUp || !verified)))
                        Button("Back") { reset() }.disabled(wallet.busy)
                    }
                    if wallet.busy { ProgressView("Opening wallet…") }
                    Text("Community edition · Powered by Pearl / Oyster").font(.caption).foregroundStyle(.secondary).padding(.top, 16)
                }.padding(26).disabled(!wallet.initialized)
            }.onChange(of: phase) { value in if value == .background { reset() } }
        }
    }

    private func action(_ title: String, perform: @escaping () async -> Void) -> some View {
        Button { Task { await perform() } } label: { Text(title).frame(maxWidth: .infinity).padding(10) }
            .buttonStyle(.borderedProminent).disabled(wallet.busy)
    }

    private func reset() {
        password = ""; confirmation = ""; phrase = ""; verification = ""; backedUp = false; mode = "welcome"
    }
}
