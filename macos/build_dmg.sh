#!/usr/bin/env bash
set -euo pipefail

# Script to build Antigravity Unlocker for macOS (.app bundle and .dmg)
# Can be run on any macOS machine with Rust installed.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="Antigravity Unlocker"
BUNDLE_NAME="${APP_NAME}.app"
BUILD_DIR="${PROJECT_ROOT}/target/macos_bundle"
APP_DIR="${BUILD_DIR}/${BUNDLE_NAME}"
DMG_NAME="Antigravity-Unlocker-macOS.dmg"
DMG_PATH="${PROJECT_ROOT}/target/${DMG_NAME}"

echo "==> Building Rust release binaries..."
# Determine targets: build Universal binary if possible, or native architecture
ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
    rustup target add aarch64-apple-darwin x86_64-apple-darwin 2>/dev/null || true
    echo "==> Building Apple Silicon (aarch64)..."
    cargo build --release --bin ag_unlocker --target aarch64-apple-darwin
    echo "==> Building Intel (x86_64)..."
    cargo build --release --bin ag_unlocker --target x86_64-apple-darwin
    
    mkdir -p "${PROJECT_ROOT}/target"
    lipo -create \
        "target/aarch64-apple-darwin/release/ag_unlocker" \
        "target/x86_64-apple-darwin/release/ag_unlocker" \
        -output "${PROJECT_ROOT}/target/ag_unlocker_universal"
    BIN_SRC="${PROJECT_ROOT}/target/ag_unlocker_universal"
else
    echo "==> Building native binary ($ARCH)..."
    cargo build --release --bin ag_unlocker
    BIN_SRC="${PROJECT_ROOT}/target/release/ag_unlocker"
fi

echo "==> Creating macOS App Bundle..."
rm -rf "${BUILD_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy binary
cp "$BIN_SRC" "${APP_DIR}/Contents/MacOS/ag_unlocker"
chmod +x "${APP_DIR}/Contents/MacOS/ag_unlocker"

# Copy Info.plist
cp "${PROJECT_ROOT}/macos/Info.plist" "${APP_DIR}/Contents/Info.plist"

# Copy icon if available or create placeholder
if [[ -f "${PROJECT_ROOT}/assets/icon.icns" ]]; then
    cp "${PROJECT_ROOT}/assets/icon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
elif [[ -f "${PROJECT_ROOT}/icon.ico" ]]; then
    # In case sips/iconutil are present
    echo "==> Note: icon.ico found. App will use standard bundle icon or icon.ico."
fi

# Ad-hoc codesign the bundle
echo "==> Code signing with ad-hoc signature..."
codesign --force --deep --sign - "${APP_DIR}" || true

echo "==> Packaging DMG..."
DMG_STAGE="${BUILD_DIR}/dmg_staging"
rm -rf "${DMG_STAGE}"
mkdir -p "${DMG_STAGE}"

# Copy App to staging
cp -R "${APP_DIR}" "${DMG_STAGE}/"

# Add symlink to Applications folder
ln -s /Applications "${DMG_STAGE}/Applications"

# Create disk image
rm -f "${DMG_PATH}"
if command -v hdiutil >/dev/null 2>&1; then
    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "${DMG_STAGE}" \
        -ov -format UDZO \
        "${DMG_PATH}"
    echo "==> DMG successfully created at: ${DMG_PATH}"
else
    echo "==> hdiutil not found (running on non-macOS). Created app bundle at ${APP_DIR}."
fi
