#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="${1:-1.0.0}"
PKG_ID="com.blik.pkg"
OUT=".build/release_build"

echo "=== Blik $VERSION — сборка ==="

# ── 0. Подстановка версии в исходники ──────────────────
echo "Подстановка версии $VERSION..."
sed -i '' "s/public static let appVersion = \".*\"/public static let appVersion = \"$VERSION\"/" \
    Sources/BlikCore/Constants.swift
# XPCConstants.protocolVersion НЕ подставляется: это версия XPC-протокола, а не релиза.
# Подстановка релизной версии (1.x) ломала capability-гейты minHelperVersionFor* (2.x).
sed -i '' "s/<string>[0-9]*\.[0-9]*\.[0-9]*<\/string>/<string>$VERSION<\/string>/g" \
    Resources/Blik-Info.plist
sed -i '' "s/<string>[0-9]*\.[0-9]*\.[0-9]*<\/string>/<string>$VERSION<\/string>/g" \
    Resources/BlikApp-Info.plist

# ── 1. Swift build release ──────────────────────────────
echo "Компиляция..."
swift build -c release --product BlikApp
swift build -c release --product blik
swift build -c release --product BlikHelper

# ── 2. Подготовка выходной директории ───────────────────
rm -rf "$OUT"
mkdir -p "$OUT"

# ── 3. Blik.app bundle (unified: GUI + MenuBar) ──────
echo "Сборка Blik.app (unified)..."
APP="$OUT/_app/Blik.app/Contents"
mkdir -p "$APP/MacOS" "$APP/Resources"

cp .build/release/BlikApp "$APP/MacOS/"
cp Resources/BlikApp-Info.plist "$APP/Info.plist"
cp Resources/uninstall-helper.sh "$APP/Resources/"
chmod +x "$APP/Resources/uninstall-helper.sh"
cp Resources/AppIcon.icns "$APP/Resources/"

# SPM resource bundle at .app root (where Bundle.module expects it)
cp -R .build/release/blik_BlikApp.bundle "$APP/Resources/" 2>/dev/null || true
cp -R .build/release/blik_BlikApp.bundle "$OUT/_app/Blik.app/" 2>/dev/null || true

codesign --force --sign - --deep "$OUT/_app/Blik.app" 2>&1 || true

# ── 4. PKG payload ──────────────────────────────────────
echo "Сборка PKG..."
ROOT="$OUT/_pkg-root"
SCRIPTS="$OUT/_pkg-scripts"

mkdir -p "$ROOT/Applications"
mkdir -p "$ROOT/Library/PrivilegedHelperTools"
mkdir -p "$ROOT/Library/LaunchDaemons"
mkdir -p "$ROOT/Library/LaunchAgents"
mkdir -p "$ROOT/usr/local/bin"

cp -R "$OUT/_app/Blik.app" "$ROOT/Applications/"
cp .build/release/BlikHelper "$ROOT/Library/PrivilegedHelperTools/com.blik.helper"
cp Resources/com.blik.helper.plist "$ROOT/Library/LaunchDaemons/"
cp Resources/com.blik.app.plist "$ROOT/Library/LaunchAgents/"
cp .build/release/blik "$ROOT/usr/local/bin/"

mkdir -p "$SCRIPTS"
cp scripts/preinstall "$SCRIPTS/"
cp scripts/postinstall "$SCRIPTS/"
chmod +x "$SCRIPTS/preinstall" "$SCRIPTS/postinstall"

# ── 5. Component PKG ────────────────────────────────────
pkgbuild \
    --root "$ROOT" \
    --scripts "$SCRIPTS" \
    --identifier "$PKG_ID" \
    --version "$VERSION" \
    --install-location "/" \
    "$OUT/_component.pkg"

# ── 6. Product PKG с визардом ───────────────────────────
cat > "$OUT/_distribution.xml" << DIST
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Blik</title>
    <welcome file="welcome.html"/>
    <conclusion file="conclusion.html"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64"/>
    <volume-check>
        <allowed-os-versions>
            <os-version min="13.0"/>
        </allowed-os-versions>
    </volume-check>
    <pkg-ref id="com.blik.pkg"/>
    <choices-outline>
        <line choice="default">
            <line choice="com.blik.pkg"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="com.blik.pkg" visible="false">
        <pkg-ref id="com.blik.pkg"/>
    </choice>
    <pkg-ref id="com.blik.pkg" version="$VERSION" onConclusion="none">
        _component.pkg
    </pkg-ref>
</installer-gui-script>
DIST

mkdir -p "$OUT/_pkg-resources"
cp Resources/welcome.html "$OUT/_pkg-resources/"
cp Resources/conclusion.html "$OUT/_pkg-resources/"

productbuild \
    --distribution "$OUT/_distribution.xml" \
    --resources "$OUT/_pkg-resources" \
    --package-path "$OUT/" \
    "$OUT/Blik-$VERSION.pkg"

# ── 7. Очистка промежуточных файлов ─────────────────────
rm -rf "$OUT/_app" "$OUT/_pkg-root" "$OUT/_pkg-scripts" "$OUT/_pkg-resources" "$OUT/_distribution.xml" "$OUT/_component.pkg"

echo ""
echo "✓ Готово: $OUT/Blik-$VERSION.pkg"
echo "  Установка: open $OUT/Blik-$VERSION.pkg"
