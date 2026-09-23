import SwiftUI
import CoreImage.CIFilterBuiltins

struct RootView: View {
    @EnvironmentObject private var wallet: WalletModel
    @State private var selectedTab = 0
    var body: some View {
        Group {
            if wallet.unlocked {
                if #available(iOS 26.0, *) {
                    walletTabs.tabBarMinimizeBehavior(.onScrollDown)
                } else { walletTabs }
            } else { OnboardingView() }
        }
    }

    private var walletTabs: some View {
        TabView(selection: $selectedTab) {
            DashboardView(onReceive: { selectedTab = 1 })
                .tabItem { Label("钱包", systemImage: "wallet.pass.fill") }.tag(0)
            ReceiveView().tabItem { Label("收款", systemImage: "qrcode") }.tag(1)
            ActivityView().tabItem { Label("记录", systemImage: "clock") }.tag(2)
            AddressBookView().tabItem { Label("地址簿", systemImage: "person.crop.rectangle.stack") }.tag(3)
            SettingsView().tabItem { Label("设置", systemImage: "gearshape") }.tag(4)
        }
        .task {
            while !Task.isCancelled {
                await wallet.refresh()
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { break }
            }
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var wallet: WalletModel
    @State private var showSend = false
    let onReceive: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Label(wallet.network == "mainnet" ? "PEARL 主网" : "PEARL 测试网", systemImage: "circle.fill")
                                .font(.caption.weight(.semibold)).foregroundStyle(PearlTheme.accent)
                            Spacer()
                            Image(systemName: "shield.lefthalf.filled").foregroundStyle(PearlTheme.accent)
                        }
                        Text("可用余额").font(.subheadline).foregroundStyle(.secondary)
                        Text(wallet.snapshot.map { PearlAmount.display($0.balance) } ?? "—")
                            .font(.system(size: 48, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText()).minimumScaleFactor(0.45).lineLimit(1)
                        Text("PRL").font(.headline).foregroundStyle(.secondary)
                        if let pending = wallet.snapshot?.pending, pending != 0 {
                            Label("待确认：\(PearlAmount.display(pending)) PRL", systemImage: "clock")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(26).frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [PearlTheme.accent.opacity(0.18), PearlTheme.highlight.opacity(0.12)],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 28))
                    .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(PearlTheme.accent.opacity(0.15)))
                    HStack(spacing: 12) {
                        Button { showSend = true } label: {
                            Label("发送", systemImage: "arrow.up.right")
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }.buttonStyle(.borderedProminent)
                            .disabled(wallet.snapshot?.synced != true || wallet.busy)
                        Button(action: onReceive) {
                            Label("收款", systemImage: "arrow.down.left")
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }.buttonStyle(.bordered)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        if wallet.snapshot?.synced == true {
                            Label("钱包已同步", systemImage: "checkmark.shield")
                        } else {
                            HStack(spacing: 9) {
                                ProgressView().tint(PearlTheme.accent)
                                Text("正在与 Pearl 节点同步")
                            }
                        }
                        if let snapshot = wallet.snapshot {
                            Text("区块头 \(snapshot.height) / \(snapshot.peerHeight)").font(.caption).foregroundStyle(.secondary)
                            if !snapshot.synced {
                                Text("钱包扫描 \(max(0, snapshot.walletHeight)) / \(snapshot.peerHeight)")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let remaining = wallet.syncRemaining {
                                    Text(SyncEstimator.label(remaining))
                                        .font(.caption.weight(.medium)).foregroundStyle(PearlTheme.accent)
                                } else {
                                    Text(snapshot.peerHeight <= 0 ? "正在连接节点…" :
                                         snapshot.peerHeight > snapshot.walletHeight
                                         ? "正在估算剩余时间…" : "正在完成交易扫描…")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Text("请保持应用打开以完成同步。导入钱包需要从区块链起点扫描。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("重新连接") { Task { await wallet.retrySync() } }.disabled(wallet.busy)
                    }
                    Text("你的私钥，你的 Pearl。").font(.title2.weight(.medium))
                    Text("交易在这台 iPhone 上签名，恢复短语不会离开钱包。")
                        .foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: 700).frame(maxWidth: .infinity)
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
                VStack(spacing: 22) {
                    Text("接收 Pearl").font(.largeTitle.bold())
                    Text("此地址仅接收\(wallet.network == "mainnet" ? "主网" : "测试网") PRL。").foregroundStyle(.secondary)
                    if !wallet.receiveAddress.isEmpty {
                        if let image = qr(wallet.receiveAddress) {
                            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                                .frame(width: 232, height: 232).padding(22)
                                .background(.white, in: RoundedRectangle(cornerRadius: 24))
                                .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
                        }
                        Text(wallet.receiveAddress)
                            .font(.system(.footnote, design: .monospaced))
                            .multilineTextAlignment(.center).textSelection(.enabled)
                            .padding(16).frame(maxWidth: .infinity)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                        HStack(spacing: 12) {
                            ShareLink(item: wallet.receiveAddress) {
                                Label("分享", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                            }.buttonStyle(.borderedProminent)
                            Button { UIPasteboard.general.string = wallet.receiveAddress } label: {
                                Label("复制", systemImage: "doc.on.doc")
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                            }.buttonStyle(.bordered)
                        }
                    } else { ProgressView("正在准备地址…") }
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
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
                        if tx.time > 0 {
                            Text(Date(timeIntervalSince1970: TimeInterval(tx.time)).formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
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
    @AppStorage("autoLockMinutes") private var autoLockMinutes = 5
    @AppStorage("lockImmediatelyOnBackground") private var lockImmediatelyOnBackground = false
    @AppStorage("backgroundNotificationsEnabled") private var backgroundNotificationsEnabled = false
    @State private var setupPassword = ""
    @State private var showExport = false
    @State private var peerDraft = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("网络") {
                    Text(wallet.network == "mainnet" ? "Pearl 主网" : "Pearl 测试网 2")
                    Text("锁定钱包后可切换网络。").font(.footnote).foregroundStyle(.secondary)
                }
                Section("同步节点") {
                    LabeledContent("当前", value: wallet.syncPeer.isEmpty ? "自动连接公共节点" : wallet.syncPeer)
                    TextField("自建节点，例如 node.example.com:44108", text: $peerDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("保存并锁定钱包") {
                        Task { await wallet.configureSyncPeer(peerDraft) }
                    }
                    .disabled(wallet.busy || peerDraft.trimmingCharacters(in: .whitespacesAndNewlines) == wallet.syncPeer)
                    Text("留空可恢复公共节点自动发现。自建地址是 Pearl P2P 节点，不是 HTTP API；节点会缓存区块链数据，手机仍会验证收到的区块头。保存后重新解锁以连接新节点。")
                        .font(.footnote).foregroundStyle(.secondary)
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
                    Label("钱包在后台超时后自动锁定", systemImage: "lock.shield")
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
                        Text("生物识别可用于解锁和转账验证。更改设备生物识别设置后，需要重新启用。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("设置设备密码并录入面容 ID 或触控 ID 后，即可启用生物识别解锁。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("请离线保存恢复短语。应用数据不会备份到 iCloud；删除应用会移除本机钱包。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("导出助记词或私钥") { showExport = true }
                        .disabled(wallet.busy)
                    Button("锁定钱包") { Task { await wallet.lock() } }
                }
                Section("自动锁定") {
                    Stepper(value: $autoLockMinutes, in: 1...60) {
                        Label("后台 \(autoLockMinutes) 分钟后锁定", systemImage: "timer")
                    }
                    Toggle("切到后台立即锁定", isOn: $lockImmediatelyOnBackground)
                    Text("前台使用时不会自动锁定。关闭立即锁定后，应用从后台返回时会检查停留时长；超过设定时间才要求重新解锁。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("通知") {
                    Toggle("后台收款提醒", isOn: $backgroundNotificationsEnabled)
                        .onChange(of: backgroundNotificationsEnabled) { enabled in
                            if enabled {
                                Task {
                                    if await BackgroundNotifications.requestPermission() {
                                        BackgroundNotifications.schedule()
                                    } else {
                                        backgroundNotificationsEnabled = false
                                        wallet.error = "未获得通知权限。请在 iOS 设置中允许 Pearl 钱包通知。"
                                    }
                                }
                            } else { BackgroundNotifications.cancel() }
                        }
                    Text("手机会在系统允许的后台刷新时检查新收款，提醒可能延迟；无需上传地址或私钥。通知不显示金额和地址。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("关于") {
                    Text("Pearl Wallet iOS · 0.5.0")
                    Text("社区分支 · 基于 Oyster 与 Pearl SPV")
                    Link("查看源代码", destination: URL(string: "https://github.com/apj9ehckiw/pearl/tree/codex/ios-wallet/apps/ios")!)
                }
            }.navigationTitle("设置")
                .onAppear { peerDraft = wallet.syncPeer }
                .sheet(isPresented: $showExport) { SecretExportView() }
                .onChange(of: phase) { value in if value == .background { setupPassword = "" } }
        }
    }
}
