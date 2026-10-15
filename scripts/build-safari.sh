#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project "Safari/疾风下载Safari助手.xcodeproj" -target "疾风下载Safari助手 Extension" -configuration Release CONFIGURATION_BUILD_DIR="$PWD/build/safari-extension" ARCHS=arm64 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGNING_ALLOWED=YES build
