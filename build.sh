#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
APP="${OUTPUT_DIR:-build}/疾风下载.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" ../module-cache
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 -module-cache-path "$(pwd -P)/../swift-build-cache" Sources/Engine.swift Sources/Bridge.swift Sources/main.swift -o "$APP/Contents/MacOS/SwiftDownload"
rm -rf "$APP/Contents/Resources/浏览器助手"
cp -R Extension "$APP/Contents/Resources/浏览器助手"
rm -rf "$APP/Contents/Resources/Firefox助手"
cp -R FirefoxExtension "$APP/Contents/Resources/Firefox助手"
if [ -n "${SAFARI_EXTENSION_PATH:-}" ]; then
  mkdir -p "$APP/Contents/PlugIns"
  ditto "$SAFARI_EXTENSION_PATH" "$APP/Contents/PlugIns/疾风下载 Safari.appex"
fi
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp extension-id.txt "$APP/Contents/Resources/extension-id.txt"
/usr/bin/python3 - "$APP" <<'PY'
import plistlib,sys
p={'CFBundleURLTypes':[{'CFBundleURLName':'疾风下载链接','CFBundleURLSchemes':['swift-download']}],'CFBundleName':'疾风下载','CFBundleDisplayName':'疾风下载','CFBundleIdentifier':'local.ultra.SwiftDownload','CFBundleExecutable':'SwiftDownload','CFBundleIconFile':'AppIcon','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.3.0','CFBundleVersion':'8','LSMinimumSystemVersion':'13.0','NSHighResolutionCapable':True,'NSAppTransportSecurity':{'NSAllowsArbitraryLoads':True},'NSHumanReadableCopyright':'Independent native download manager. 2026.'}
with open(sys.argv[1]+'/Contents/Info.plist','wb') as f:plistlib.dump(p,f)
PY
for name in yt-dlp ffmpeg deno; do test -x "Runtime/$name" || { echo "先运行 python3 scripts/prepare-runtime.py"; exit 1; }; done
if [ -d Runtime ]; then
  mkdir -p "$APP/Contents/Resources/Tools"
  cp Runtime/yt-dlp Runtime/ffmpeg Runtime/deno "$APP/Contents/Resources/Tools/"
  for tool in "$APP/Contents/Resources/Tools/"*; do codesign --force --sign - "$tool"; done
fi
if [ -d "$APP/Contents/PlugIns" ]; then
  codesign --force --sign - --preserve-metadata=entitlements "$APP/Contents/PlugIns/疾风下载 Safari.appex"
  codesign -d --entitlements - --xml "$APP/Contents/PlugIns/疾风下载 Safari.appex" | /usr/bin/python3 -c 'import plistlib,sys; d=plistlib.loads(sys.stdin.buffer.read()); assert d.get("com.apple.security.app-sandbox") and d.get("com.apple.security.network.client"), "Safari entitlements missing"'
fi
cp -R ThirdParty "$APP/Contents/Resources/ThirdParty"
codesign --force --sign - "$APP"
