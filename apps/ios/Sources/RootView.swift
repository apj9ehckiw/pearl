import SwiftUI
import CoreImage.CIFilterBuiltins

struct RootView: View {
    @EnvironmentObject private var wallet: WalletModel
    var body: some View {
        Group {
            if wallet.unlocked {
                TabView {
                    DashboardView().tabItem { Label("钱包", systemImage: "circle.hexagongrid.fill") }
                    ReceiveView().tabItem { Label("收款", systemImage: "qrcode") }
                    ActivityView().tabItem { Label("记录", systemImage: "clock") }
                    SettingsView().tabItem { Label("设置", systemImage: "gearshape") }
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
                        Label(wallet.network == "mainnet" ? "PEARL 主网" : "PEARL 测试网", systemImage: "circle.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(.teal)
                        Spacer()
                        Image(systemName: "shield.lefthalf.filled").foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("可用余额").foregroundStyle(.secondary)
                        Text(wallet.snapshot.map { PearlAmount.display($0.balance) } ?? "—")
                            .font(.system(size: 46, weight: .semibold, design: .rounded)).minimumScaleFactor(0.4).lineLimit(1)
                        Text("PRL").font(.title3).foregroundStyle(.secondary)
                        if let pending = wallet.snapshot?.pending, pending != 0 {
                            Text("待确认：\(PearlAmount.display(pending)) PRL").font(.footnote)
                        }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 26))
                    Button { showSend = true } label: {
                        Label("发送 Pearl", systemImage: "arrow.up.right").frame(maxWidth: .infinity).padding(10)
                    }.buttonStyle(.borderedProminent).disabled(wallet.snapshot?.synced != true || wallet.busy)
                    VStack(alignment: .leading, spacing: 8) {
                        Label(wallet.snapshot?.synced == true ? "钱包已同步" : "正在与 Pearl 节点同步",
                              systemImage: wallet.snapshot?.synced == true ? "checkmark.shield" : "arrow.triangle.2.circlepath")
                        if let snapshot = wallet.snapshot {
                            Text("区块头 \(snapshot.height) / \(snapshot.peerHeight)").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("请保持应用打开以完成同步。导入钱包需要从区块链起点扫描。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("重新连接") { Task { await wallet.retrySync() } }.disabled(wallet.busy)
                    }
                    Text("你的私钥，你的 Pearl。").font(.title2.weight(.medium))
                    Text("交易在这台 iPhone 上签名，恢复短语不会离开钱包。")
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
                    Text("接收 Pearl").font(.largeTitle.bold())
                    Text("此地址仅接收\(wallet.network == "mainnet" ? "主网" : "测试网") PRL。").foregroundStyle(.secondary)
                    if !wallet.receiveAddress.isEmpty {
                        if let image = qr(wallet.receiveAddress) {
                            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                                .frame(width: 240, height: 240).padding(20).background(.white, in: RoundedRectangle(cornerRadius: 20))
                        }
                        Text(wallet.receiveAddress).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        ShareLink(item: wallet.receiveAddress) { Label("分享地址", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.borderedProminent)
                        Button("复制地址") { UIPasteboard.general.string = wallet.receiveAddress }
                    } else { ProgressView("正在准备地址…") }
                }.padding(24)
            }.navigationTitle("收款").navigationBarTitleDisplayMode(.inline)
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
                        Text("暂无交易").font(.headline)
                        Text("钱包同步后，收款和付款记录会显示在这里。").foregroundStyle(.secondary)
                    }.padding(.vertical, 20)
                }
                ForEach(Array(transactions.enumerated()), id: \.offset) { _, tx in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Label(tx.amount < 0 ? "发送" : "接收", systemImage: tx.amount < 0 ? "arrow.up.right" : "arrow.down.left")
                            Spacer()
                            Text("\(NSDecimalNumber(decimal: tx.amount).stringValue) PRL").fontWeight(.medium)
                        }
                        Text(tx.confirmations > 0 ? "\(tx.confirmations) 次确认" : "待确认").font(.caption).foregroundStyle(.secondary)
                        Text(tx.txid).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                    }.padding(.vertical, 6)
                }
                if transactions.count >= 50 { Text("仅显示最近 50 笔交易").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("交易记录").refreshable { await wallet.refresh() }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var wallet: WalletModel
    @Environment(\.scenePhase) private var phase
    @AppStorage("appearance") private var appearance = "system"
    @State private var setupPassword = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("网络") {
                    Text(wallet.network == "mainnet" ? "Pearl 主网" : "Pearl 测试网 2")
                    Text("锁定钱包后可切换网络。").font(.footnote).foregroundStyle(.secondary)
                }
                Section("外观") {
                    Picker("显示模式", selection: $appearance) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                }
                Section("安全") {
                    Label("钱包已加密并保存在本机", systemImage: "iphone.gen3")
                    Label("应用进入后台时自动锁定", systemImage: "lock.shield")
                    if let name = wallet.biometricName {
                        if wallet.biometricEnabled {
                            Label("已启用\(name)解锁", systemImage: name == "触控 ID" ? "touchid" : "faceid")
                            Button("关闭生物识别解锁") { Task { await wallet.disableBiometrics() } }
                                .disabled(wallet.busy)
                        } else {
                            SecureField("输入钱包密码以启用\(name)", text: $setupPassword)
                                .textContentType(.password)
                            Button("启用\(name)解锁") {
                                let secret = setupPassword
                                setupPassword = ""
                                Task { _ = await wallet.enableBiometrics(password: secret) }
                            }.disabled(setupPassword.isEmpty || wallet.busy)
                        }
                        Text("生物识别只用于解锁；发送交易仍需钱包密码。更改设备生物识别设置后，需要重新启用。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("设置设备密码并录入面容 ID 或触控 ID 后，即可启用生物识别解锁。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("请离线保存恢复短语。应用数据不会备份到 iCloud；删除应用会移除本机钱包。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("锁定钱包") { Task { await wallet.lock() } }
                }
                Section("关于") {
                    Text("Pearl Wallet iOS · 0.2.0")
                    Text("社区分支 · 基于 Oyster 与 Pearl SPV")
                    Link("查看源代码", destination: URL(string: "https://github.com/apj9ehckiw/pearl/tree/codex/ios-wallet/apps/ios")!)
                }
            }.navigationTitle("设置")
                .onChange(of: phase) { value in if value == .background { setupPassword = "" } }
        }
    }
}
