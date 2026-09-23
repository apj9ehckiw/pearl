# Pearl Wallet for iOS

Independent, on-device iOS wallet built on the upstream Oyster Go wallet and
Pearl SPV implementation, with a native SwiftUI interface. This is a community
fork, not an official Pearl Research Labs release.

## Features

- Create a 24-word BIP39 wallet, with backup verification before creation.
- Restore an Oyster-compatible BIP39 mnemonic (no extra BIP39 passphrase).
- Private keys encrypted by Oyster in the app sandbox; no remote wallet service.
- SPV synchronization through public peers or a user-selected self-hosted Pearl
  P2P node, with **XMSS and ZK verification enabled**.
- BIP86 Pearl receiving address, QR code and share sheet.
- Local, network-specific address book with validated destinations and send-time picking.
- Confirmed/pending balances, latest 50 activity entries, local signing and broadcast.
- Wallet dashboard shows the last completed sync time for the selected network;
  the send form has a keyboard-dismiss control for numeric entry.
- Animated synchronization indicator and a rough ETA based on wallet scan progress.
- Mainnet and testnet2 with separate databases.
- Simplified Chinese interface with system, light and dark appearance options.
- Light blue accent throughout the native interface.
- Optional Face ID / Touch ID unlock and transfer approval after a password check.
  The credential is held in a device-only Keychain
  item that requires a device passcode and the current biometric enrollment.
- Native iOS 26 Liquid Glass tab bar when built with Xcode 26; standard system
  tab bar remains on earlier iOS versions.
- Privacy cover when inactive, auto-lock after a user-selected 1–60 minutes in
  the background, and an optional immediate lock when the app backgrounds.
- Optional private local notifications for new incoming transactions. iOS schedules
  opportunistic background refreshes, so delivery can be delayed or skipped.
- Password-gated export of the encrypted recovery phrase or the current BIP86
  receiving address's internal WIF key. Exported content hides after one minute.
- App data excluded from cloud backup. Keep the recovery phrase offline.

The app should stay in the foreground for initial synchronization. Restoring scans
from genesis, which can take time and storage. Background refresh is short and
system-controlled; synchronization resumes when the app becomes active. Locking
closes the database and peer connections. No RPC port is opened on the phone.
The auto-lock timer does not run while the app is in the foreground. Because iOS
can suspend apps, the background duration is checked before showing the wallet
again; enabling immediate background lock closes it at once.
To use your own chain-data cache, follow the
[self-hosted node deployment guide](../../deploy/ios-sync-node/README.md), then
enter its host and P2P port under Settings → Sync Node. This endpoint is not an
HTTP API; a header-only HTTP service cannot supply the compact filters and
blocks needed by this wallet. Public peer discovery remains available by
clearing the setting. Each network has its own endpoint.
The encrypted recovery phrase is saved only for wallets created or imported by
this version. Earlier wallet databases cannot reconstruct the original BIP39
words; use the offline backup made at creation. The single-address WIF needs a
wallet that handles BIP86 Taproot tweaking and cannot restore the whole wallet.
If biometrics change or are unavailable, unlock with the wallet password and
enable biometric unlock again. Biometric credentials are separate per network
and do not migrate to another device.

## GitHub Actions build

Work is maintained at https://github.com/apj9ehckiw/pearl on `codex/ios-wallet`.
The original repository is only an upstream source; do not open an upstream PR.

Push to that branch to start **Pearl iOS Wallet**, or use its Run workflow button
once the workflow is available on the fork's default branch. The workflow has an
explicit fork repository guard, read-only token permissions and no signing secrets.

The macOS 26 runner builds with Xcode 26. It builds the Rust verifier and C/C++ XMSS libraries separately for
iPhone ARM64 and simulator ARM64, binds the Go core with gomobile, generates an
Xcode project, runs simulator tests and archives the device app.

Download `PearlWallet-iOS-<run number>` from the successful run's Artifacts:

| Artifact | Purpose |
| --- | --- |
| `PearlWallet-unsigned.ipa` | Device app for signing with your Apple identity / sideloading tool |
| `PearlWallet.xcarchive` | Archive for signing/exporting on a Mac |
| `Debug-iphonesimulator/PearlWallet.app` | Apple Silicon iOS simulator app |

**The unsigned IPA is not directly installable.** For normal device distribution,
use an Apple development/distribution certificate and a matching provisioning
profile. App Store / TestFlight upload is not configured. Never commit a signing
certificate, profile, wallet seed or password into this repository.

## Build locally (Mac with Xcode)

Requires Go as specified in `go.mod`, stable Rust, Xcode 26 + command line tools,
and XcodeGen (`brew install xcodegen`). From the repository root:

```sh
go install golang.org/x/mobile/cmd/gomobile@v0.0.0-20260908204917-8b95e45f8d3e
go install golang.org/x/mobile/cmd/gobind@v0.0.0-20260908204917-8b95e45f8d3e
gomobile init
bash mobile/build-ios.sh
cd apps/ios
sips --padToHeightWidth 564 564 Resources/Assets.xcassets/AppIcon.appiconset/Icon.png
sips --resampleHeightWidth 1024 1024 Resources/Assets.xcassets/AppIcon.appiconset/Icon.png
xcodegen generate
open PearlWallet.xcodeproj
```

Select your signing team and a bundle ID registered to your account for a device
build. The generated Xcode project and compiled frameworks are build outputs and
are not committed. Build from a clean checkout when rebuilding the XCFramework.

## Validation

`go test ./mobile/core` checks BIP39 generation, network/amount validation and
lifecycle guards, password verification and key relocking, encrypted recovery
export, watch-mode opening, offline SPV shutdown and receiving address/key
derivation without native libraries. The iOS workflow builds with both
`xmss,zkpow` production tags and executes XCTest amount parsing tests on a simulator.
Building successfully does not constitute a real-funds or mainnet recovery test;
verify Face ID / Touch ID on an enrolled physical device, restore,
synchronization and send/receive on testnet before holding funds.

## Layout

- `mobile/core`: serialized Go wallet lifecycle and Swift-compatible API.
- `mobile/build-ios.sh`: cross-compilation and XCFramework assembly.
- `apps/ios/Sources`: native SwiftUI screens and actor-isolated bridge.
- `apps/ios/Tests`: exact atomic amount parsing tests.
- `.github/workflows/pearl-ios-wallet.yml`: fork-only build and artifact upload.

The upstream ISC license and attribution are retained; see the root LICENSE.
