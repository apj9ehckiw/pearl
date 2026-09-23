#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/apps/ios/Frameworks"
mkdir -p "$OUT" "$ROOT/build/ios" "$ROOT/zk-pow/bindings/go/target/release"
export IPHONEOS_DEPLOYMENT_TARGET=16.0
export CGO_ENABLED=1
export CGO_LDFLAGS_ALLOW='.*'

# Generate the consensus verifier data on the host before cross-compiling.
(cd zk-pow && cargo run --locked --release --no-default-features --bin build_cache src/circuit/v2_cache.bin src/v1/v1_cache.bin)

for platform in device simulator; do
  if [[ "$platform" == device ]]; then
    SDK=iphoneos; TARGET=aarch64-apple-ios; GO_TARGET=ios/arm64; CLANG_TARGET=arm64-apple-ios16.0
  else
    SDK=iphonesimulator; TARGET=aarch64-apple-ios-sim; GO_TARGET=iossimulator/arm64; CLANG_TARGET=arm64-apple-ios16.0-simulator
  fi
  SDKROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
  export SDKROOT
  rustup target add "$TARGET"
  (cd zk-pow/bindings/go && cargo build --locked --release --target "$TARGET")
  cp "zk-pow/bindings/go/target/$TARGET/release/libzk_pow_ffi.a" zk-pow/bindings/go/target/release/libzk_pow_ffi.a
  make -C xmss -B libxmss.a \
    CC="$(xcrun --sdk "$SDK" --find clang)" CXX="$(xcrun --sdk "$SDK" --find clang++)" \
    AR="$(xcrun --sdk "$SDK" --find ar)" \
    CFLAGS="-O2 -target $CLANG_TARGET -isysroot $SDKROOT" \
    CXXFLAGS="-O2 -std=c++11 -target $CLANG_TARGET -isysroot $SDKROOT"
  mkdir -p "build/ios/$platform"
  gomobile bind -target="$GO_TARGET" -iosversion=16.0 -tags=xmss,zkpow \
    -o "build/ios/$platform/PearlCore.xcframework" ./mobile/core
  # Go's c-archive carries references to external CGO libraries, not their
  # object code. Merge both native archives into each framework slice so
  # Xcode can resolve XMSS and verifier symbols when linking the final app.
  FRAMEWORK="$(find "$ROOT/build/ios/$platform" -type d -name PearlCore.framework | head -1)"
  xcrun libtool -static -o "$ROOT/build/ios/$platform/combined.a" \
    "$FRAMEWORK/PearlCore" "$ROOT/xmss/libxmss.a" \
    "$ROOT/zk-pow/bindings/go/target/$TARGET/release/libzk_pow_ffi.a"
  mv "$ROOT/build/ios/$platform/combined.a" "$FRAMEWORK/PearlCore"
done
unset SDKROOT
DEVICE="$(find "$ROOT/build/ios/device" -type d -name PearlCore.framework | head -1)"
SIMULATOR="$(find "$ROOT/build/ios/simulator" -type d -name PearlCore.framework | head -1)"
xcodebuild -create-xcframework -framework "$DEVICE" -framework "$SIMULATOR" -output "$OUT/PearlCore.xcframework"
