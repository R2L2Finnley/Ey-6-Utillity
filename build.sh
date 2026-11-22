#!/bin/bash
# Baut eine unsignierte IPA (Sideloadly / AltStore signieren sie beim Installieren neu).
# Läuft auf macOS mit Xcode, also auch auf GitHub Actions.
set -euo pipefail
cd "$(dirname "$0")"

APP=EY6Control
OUT=build
rm -rf "$OUT"
mkdir -p "$OUT/Payload/$APP.app" "$OUT/actool"
BUNDLE="$OUT/Payload/$APP.app"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)

echo "== Swift kompilieren"
xcrun --sdk iphoneos swiftc -parse-as-library -O -swift-version 5 \
  -target arm64-apple-ios14.0 -sdk "$SDK" \
  -framework UIKit -framework WebKit -framework CoreBluetooth \
  Sources/*.swift -o "$BUNDLE/$APP"

echo "== Ressourcen kopieren"
cp Resources/Info.plist "$BUNDLE/Info.plist"
cp Resources/index.html Resources/bridge.js "$BUNDLE/"
printf 'APPL????' > "$BUNDLE/PkgInfo"

echo "== Symbole und Startfarbe (Asset-Katalog)"
if xcrun actool Resources/Assets.xcassets --compile "$BUNDLE" \
     --platform iphoneos --minimum-deployment-target 14.0 \
     --app-icon AppIcon --target-device iphone --target-device ipad \
     --output-partial-info-plist "$OUT/actool/partial.plist" > "$OUT/actool/log.txt" 2>&1; then
  /usr/libexec/PlistBuddy -c "Merge $OUT/actool/partial.plist" "$BUNDLE/Info.plist" || true
else
  echo "WARNUNG: actool fehlgeschlagen, App wird ohne Symbol gebaut"
  cat "$OUT/actool/log.txt"
fi

echo "== IPA packen"
(cd "$OUT" && zip -qry "$APP.ipa" Payload)
ls -lh "$OUT/$APP.ipa"
