#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
RUN=$(mktemp -d "${TMPDIR:-/tmp/}swift-download-tests.XXXXXX")
PORT_FILE="$RUN/port" python3 Tests/server.py > "$RUN/server.log" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT
for n in {1..50}; do test -s "$RUN/port" && break; sleep 0.1; done
PORT=$(cat "$RUN/port")
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 -module-cache-path "$RUN/module-cache" Sources/Engine.swift Tests/EngineTests.swift -o "$RUN/engine-tests"
"$RUN/engine-tests" "http://127.0.0.1:$PORT" "$RUN/Run"
node Tests/extension-tests.mjs
printf '测试文件保存在 %s\n' "$RUN"

node Tests/video-tests.mjs
