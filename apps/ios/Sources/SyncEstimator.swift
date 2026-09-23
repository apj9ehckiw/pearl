import Foundation

struct SyncEstimator {
    private var lastHeight: Int?
    private var lastAdvance: Date?
    private var blocksPerSecond: Double?

    mutating func update(walletHeight: Int, peerHeight: Int, synced: Bool,
                         now: Date = Date()) -> TimeInterval? {
        guard !synced, walletHeight >= 0, peerHeight > walletHeight else {
            if synced { self = SyncEstimator() }
            return nil
        }
        if let lastHeight, let lastAdvance, walletHeight > lastHeight {
            let elapsed = now.timeIntervalSince(lastAdvance)
            if elapsed >= 2 {
                let observed = Double(walletHeight - lastHeight) / elapsed
                blocksPerSecond = blocksPerSecond.map { 0.3 * observed + 0.7 * $0 } ?? observed
                self.lastHeight = walletHeight
                self.lastAdvance = now
            }
        } else if lastHeight == nil || walletHeight < lastHeight! {
            self.lastHeight = walletHeight
            self.lastAdvance = now
            blocksPerSecond = nil
        }
        guard let rate = blocksPerSecond, rate > 0,
              let lastAdvance, now.timeIntervalSince(lastAdvance) < 90 else { return nil }
        let seconds = Double(peerHeight - walletHeight) / rate
        return seconds.isFinite && seconds < 7 * 24 * 3600 ? max(0, seconds) : nil
    }

    static func label(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "预计不到 1 分钟" }
        if seconds < 3600 { return "预计约 \(Int(ceil(seconds / 60))) 分钟" }
        if seconds < 24 * 3600 { return "预计约 \(Int(ceil(seconds / 3600))) 小时" }
        return "预计约 \(Int(ceil(seconds / (24 * 3600)))) 天"
    }
}
