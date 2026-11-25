#!/bin/zsh
# Build (Release, Developer ID), install to ~/Applications, register the Finder extension.
set -euo pipefail
cd "${0:A:h}/.."

BUNDLE_ID=com.rak.indirilenlerisil
EXT_ID=$BUNDLE_ID.FinderExt
DEST="$HOME/Applications/IndirilenleriSil.app"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# The token is made once per checkout, not per build: app and extension always get the same one,
# and an extension process that outlives a reinstall keeps talking to the new app.
[[ -f Config/Token.xcconfig ]] || print -r -- "IS_TOKEN = $(openssl rand -hex 16)" > Config/Token.xcconfig
[[ -f App/AppIcon.icns ]] || xcrun swift scripts/make-icon.swift App/AppIcon.icns
xcodegen generate --quiet

xcodebuild -project IndirilenleriSil.xcodeproj -scheme IndirilenleriSil -configuration Release \
  -derivedDataPath build/dd build -quiet
BUILT=build/dd/Build/Products/Release/IndirilenleriSil.app
codesign -v --deep --strict "$BUILT"

# Replace only our own previous install.
if [[ -e "$DEST" ]]; then
  [[ "$(plutil -extract CFBundleIdentifier raw "$DEST/Contents/Info.plist")" == "$BUNDLE_ID" ]] || { print -u2 "$DEST başka bir uygulama; dokunulmadı"; exit 1; }
  if pgrep -x IndirilenleriSil >/dev/null; then
    print -u2 "İndirilenleri Sil şu an çalışıyor (bir iş sürüyor olabilir); bitince tekrar deneyin."; exit 1
  fi
  rm -rf "$DEST"
fi
ditto "$BUILT" "$DEST"

# Only the installed copy may own the URL scheme and the extension. Deleting the build copy is
# enough; `pluginkit -r` / `lsregister -u` on it also dropped the installed copy's registration
# (observed 2026-09-27: "Could not find specified service" in Finder right after an install).
rm -rf "$BUILT"
"$LSREG" -f -R "$DEST"

# Exactly one copy of the extension may be registered, and it has to be the installed one.
registered_paths() { pluginkit -mAv -i "$EXT_ID" | awk -F'\t' -v id="$EXT_ID" 'index($0, id) { print $NF }'; }
registered() { [[ "$(registered_paths)" == "$DEST/Contents/PlugIns/FinderExt.appex" ]]; }
for attempt in 1 2 3; do
  pluginkit -a "$DEST/Contents/PlugIns/FinderExt.appex"
  pluginkit -e use -i "$EXT_ID"
  sleep 5
  registered && break
  print -u2 "uzantı kaydı tutmadı, tekrar ($attempt)"
done
registered || { print -u2 "HATA: Finder uzantısı tek ve kurulu kopya olarak kayıtlı değil:"; registered_paths >&2; exit 1; }

# The extension reaches the app through its URL scheme: that, too, must lead to the installed copy.
handler=$(osascript -l JavaScript -e 'ObjC.import("AppKit"); var u = $.NSWorkspace.sharedWorkspace.URLForApplicationToOpenURL($.NSURL.URLWithString("indirilenlerisil://x")); u.isNil() ? "" : ObjC.unwrap(u.path)')
[[ "$handler" == "$DEST" ]] || { print -u2 "HATA: indirilenlerisil:// şemasını başka bir kopya açıyor: ${handler:-yok}"; exit 1; }

print "kuruldu: $DEST"
pluginkit -mAv -i "$EXT_ID"
