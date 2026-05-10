#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
APP_BUNDLE="$BUILD_DIR/Muxy.app"
APP_DEST="/Applications/Muxy.app"
ARCH="$(uname -m)"
VERSION=""
BUILD_NUMBER=""
SIGN_IDENTITY="-"

usage() {
    echo "Usage: $0 [--destination <path>] [--version <X.Y.Z>] [--build-number <number>] [--sign-identity <identity>]"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --destination)
            APP_DEST="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --build-number)
            BUILD_NUMBER="$2"
            shift 2
            ;;
        --sign-identity)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
    echo "Error: unsupported architecture '$ARCH'"
    exit 1
fi

if [[ -z "$VERSION" ]]; then
    if TAG=$(git -C "$PROJECT_ROOT" describe --tags --abbrev=0 2>/dev/null); then
        VERSION="${TAG#v}"
    else
        VERSION="0.0.0"
    fi
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: version must be in X.Y.Z format"
    exit 1
fi

if [[ -z "$BUILD_NUMBER" ]]; then
    if BUILD_NUMBER=$(git -C "$PROJECT_ROOT" rev-list --count HEAD 2>/dev/null); then
        :
    else
        BUILD_NUMBER="1"
    fi
fi

TRIPLE="${ARCH}-apple-macosx14.0"
SPARKLE_FRAMEWORK="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

echo "==> Building release binary"
cd "$PROJECT_ROOT"
swift build -c release --triple "$TRIPLE"
SPM_BUILD_DIR=$(swift build -c release --triple "$TRIPLE" --show-bin-path)

if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "Error: Sparkle.framework not found at $SPARKLE_FRAMEWORK"
    exit 1
fi

echo "==> Creating app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

cp "$SPM_BUILD_DIR/Muxy" "$APP_BUNDLE/Contents/MacOS/Muxy"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_BUNDLE/Contents/MacOS/Muxy"

if [[ -d "$SPM_BUILD_DIR/Muxy_Muxy.bundle" ]]; then
    cp -R "$SPM_BUILD_DIR/Muxy_Muxy.bundle" "$APP_BUNDLE/Contents/Resources/Muxy_Muxy.bundle"
fi

cp "$PROJECT_ROOT/Muxy/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"
"$SCRIPT_DIR/create-icns.sh" "$APP_BUNDLE/Contents/Resources/AppIcon.icns" >/dev/null
cp -R "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "==> Ad-hoc signing app bundle"
    /usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
else
    SPARKLE_DIR="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

    echo "==> Signing Sparkle.framework"
    /usr/bin/codesign --force --options runtime --preserve-metadata=entitlements \
        --sign "$SIGN_IDENTITY" \
        "$SPARKLE_DIR/Versions/B/XPCServices/Installer.xpc"
    /usr/bin/codesign --force --options runtime --preserve-metadata=entitlements \
        --sign "$SIGN_IDENTITY" \
        "$SPARKLE_DIR/Versions/B/XPCServices/Downloader.xpc"
    /usr/bin/codesign --force --options runtime --preserve-metadata=entitlements \
        --sign "$SIGN_IDENTITY" \
        "$SPARKLE_DIR/Versions/B/Updater.app"
    /usr/bin/codesign --force --options runtime --preserve-metadata=entitlements \
        --sign "$SIGN_IDENTITY" \
        "$SPARKLE_DIR/Versions/B/Autoupdate"
    /usr/bin/codesign --force --options runtime \
        --sign "$SIGN_IDENTITY" \
        "$SPARKLE_DIR"
    echo "==> Signing app bundle"
    /usr/bin/codesign --force --options runtime \
        --entitlements "$PROJECT_ROOT/Muxy/Muxy.entitlements" \
        --sign "$SIGN_IDENTITY" \
        "$APP_BUNDLE"
fi

echo "==> Installing to $APP_DEST"
if [[ -w "$(dirname "$APP_DEST")" ]]; then
    rm -rf "$APP_DEST"
    /usr/bin/ditto "$APP_BUNDLE" "$APP_DEST"
    /usr/bin/xattr -dr com.apple.quarantine "$APP_DEST" || true
else
    sudo rm -rf "$APP_DEST"
    sudo /usr/bin/ditto "$APP_BUNDLE" "$APP_DEST"
    sudo /usr/bin/xattr -dr com.apple.quarantine "$APP_DEST" || true
fi

echo "==> Installed: $APP_DEST"
