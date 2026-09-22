import SwiftUI
import CoreImage.CIFilterBuiltins

struct RootView: View {
    @EnvironmentObject private var wallet: WalletModel
    var body: some View {
        Group {
            if wallet.unlocked {
                TabView {
                    DashboardView().tabItem { Label("Wallet", systemImage: "circle.hexagongrid.fill") }
                    ReceiveView().tabItem { Label("Receive", systemImage: "qrcode") }
                    ActivityView().tabItem { Label("Activity", systemImage: "clock") }
                    SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
                }
                .task {
                    while !Task.isCancelled {
                        await wallet.refresh()
                        do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { break }
                    }
                }
            } else { OnboardingView() }
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var wallet: WalletModel
    @State private var showSend = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack {
                        Label(wallet.network == "mainnet" ? "PEARL MAINNET" : "PEARL TESTNET", systemImage: "circle.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(.teal)
                        Spacer()
                        Image(systemName: "shield.lefthalf.filled").foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your balance").foregroundStyle(.secondary)
                        Text(wallet.snapshot.map { PearlAmount.display($0.balance) } ?? "—")
                            .font(.system(size: 46, weight: .semibold, design: .rounded)).minimumScaleFactor(0.4).lineLimit(1)
                        Text("PRL").font(.title3).foregroundStyle(.secondary)
                        if let pending = wallet.snapshot?.pending, pending != 0 {
                            Text("Pending: \(PearlAmount.display(pending)) PRL").font(.footnote)
                        }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 26))
                    Button { showSend = true } label: {
                        Label("Send Pearl", systemImage: "arrow.up.right").frame(maxWidth: .infinity).padding(10)
                    }.buttonStyle(.borderedProminent).disabled(wallet.snapshot?.synced != true || wallet.busy)
                    VStack(alignment: .leading, spacing: 8) {
                        Label(wallet.snapshot?.synced == true ? "Wallet is synchronized" : "Synchronizing with Pearl peers",
                              systemImage: wallet.snapshot?.synced == true ? "checkmark.shield" : "arrow.triangle.2.circlepath")
                        if let snapshot = wallet.snapshot {
                            Text("Headers \(snapshot.height) / \(snapshot.peerHeight)").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Keep the app open for sync. Recovery scans from the beginning of the chain.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Reconnect") { Task { await wallet.retrySync() } }.disabled(wallet.busy)
                    }
                    Text("Your keys. Your Pearl.").font(.title2.weight(.medium))
                    Text("Transactions are signed on this iPhone. Your recovery phrase never leaves the wallet.")
                        .foregroundStyle(.secondary)
                }.padding(24)
            }.navigationTitle("Pearl")
                .toolbar { Button { Task { await wallet.lock() } } label: { Image(systemName: "lock") } }
                .refreshable { await wallet.refresh() }
                .sheet(isPresented: $showSend) { SendView() }
        }
    }
}

struct ReceiveView: View {
    @EnvironmentObject private var wallet: WalletModel
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Receive Pearl").font(.largeTitle.bold())
                    Text("Only send \(wallet.network == "mainnet" ? "mainnet" : "testnet") PRL to this address.").foregroundStyle(.secondary)
                    if !wallet.receiveAddress.isEmpty {
                        if let image = qr(wallet.receiveAddress) {
                            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                                .frame(width: 240, height: 240).padding(20).background(.white, in: RoundedRectangle(cornerRadius: 20))
                        }
                        Text(wallet.receiveAddress).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        ShareLink(item: wallet.receiveAddress) { Label("Share address", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.borderedProminent)
                        Button("Copy address") { UIPasteboard.general.string = wallet.receiveAddress }
                    } else { ProgressView("Preparing address…") }
                }.padding(24)
            }.navigationTitle("Receive").navigationBarTitleDisplayMode(.inline)
        }
    }

    private func qr(_ address: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(address.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}

struct ActivityView: View {
    @EnvironmentObject private var wallet: WalletModel
    var body: some View {
        NavigationStack {
            List {
                let transactions = wallet.snapshot?.transactions ?? []
                if transactions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No transactions yet").font(.headline)
                        Text("Incoming and outgoing transfers appear here as your wallet syncs.").foregroundStyle(.secondary)
                    }.padding(.vertical, 20)
                }
                ForEach(Array(transactions.enumerated()), id: \.offset) { _, tx in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Label(tx.category.capitalized, systemImage: tx.amount < 0 ? "arrow.up.right" : "arrow.down.left")
                            Spacer()
                            Text("\(NSDecimalNumber(decimal: tx.amount).stringValue) PRL").fontWeight(.medium)
                        }
                        Text(tx.confirmations > 0 ? "\(tx.confirmations) confirmations" : "Pending").font(.caption).foregroundStyle(.secondary)
                        Text(tx.txid).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                    }.padding(.vertical, 6)
                }
                if transactions.count >= 50 { Text("Showing the latest 50 entries").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("Activity").refreshable { await wallet.refresh() }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var wallet: WalletModel
    var body: some View {
        NavigationStack {
            Form {
                Section("Network") {
                    Text(wallet.network == "mainnet" ? "Pearl Mainnet" : "Pearl Testnet 2")
                    Text("Lock the wallet to switch networks.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Security") {
                    Label("Encrypted wallet stored on this device", systemImage: "iphone.gen3")
                    Label("Locks when the app enters background", systemImage: "lock.shield")
                    Text("Keep your recovery phrase offline. App data is excluded from iCloud backup; deleting the app removes its wallet.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Lock wallet") { Task { await wallet.lock() } }
                }
                Section("About") {
                    Text("Pearl Wallet for iOS · 0.1.0")
                    Text("Community fork · Built on Oyster and Pearl SPV")
                    Link("Source code", destination: URL(string: "https://github.com/apj9ehckiw/pearl/tree/codex/ios-wallet/apps/ios")!)
                }
            }.navigationTitle("Settings")
        }
    }
}
