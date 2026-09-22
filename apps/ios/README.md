# Pearl Wallet for iOS

Independent, on-device iOS wallet built on the upstream Oyster Go wallet and
Pearl SPV implementation, with a native SwiftUI interface. This is a community
fork, not an official Pearl Research Labs release.

## Features

- Create a 24-word BIP39 wallet, with backup verification before creation.
- Restore an Oyster-compatible BIP39 mnemonic (no extra BIP39 passphrase).
- Private keys encrypted by Oyster in the app sandbox; no remote wallet service.
- Direct SPV synchronization, with **XMSS and ZK verification enabled**.
- BIP86 Pearl receiving address, QR code and share sheet.
- Confirmed/pending balances, latest 50 activity entries, local signing and broadcast.
- Mainnet and testnet2 with separate databases.
- Password required to open and sign, privacy cover when inactive, lock on background.
- App data excluded from cloud backup. Keep the recovery phrase offline.

The app must stay in the foreground to sync. Restoring scans from genesis, which
can take time and storage. Backgrounding closes the database and peer connections;
unlocking resumes from saved state. No RPC port is opened on the phone.

## GitHub Actions build

Work is maintained at https://github.com/apj9ehckiw/pearl on `codex/ios-wallet`.
The original repository is only an upstream source; do not open an upstream PR.

Push to that branch to start **Pearl iOS Wallet**, or use its Run workflow button
once the workflow is available on the fork's default branch. The workflow has an
explicit fork repository guard, read-only token permissions and no signing secrets.

The macOS runner builds the Rust verifier and C/C++ XMSS libraries separately for
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

Requires Go as specified in `go.mod`, stable Rust, Xcode + command line tools,
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
lifecycle guards, encrypted database reopen, offline SPV shutdown and receiving
address persistence without native libraries. The iOS workflow builds with both
`xmss,zkpow` production tags and executes XCTest amount parsing tests on a simulator.
Building successfully does not constitute a real-funds or mainnet recovery test;
verify restore, synchronization and send/receive on testnet before holding funds.

## Layout

- `mobile/core`: serialized Go wallet lifecycle and Swift-compatible API.
- `mobile/build-ios.sh`: cross-compilation and XCFramework assembly.
- `apps/ios/Sources`: native SwiftUI screens and actor-isolated bridge.
- `apps/ios/Tests`: exact atomic amount parsing tests.
- `.github/workflows/pearl-ios-wallet.yml`: fork-only build and artifact upload.

The upstream ISC license and attribution are retained; see the root LICENSE.
