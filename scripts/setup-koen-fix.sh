#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_FILE="${PROJECT_DIR}/Sources/KoEnFix.swift"

APP_DIR="/Applications/KoEnFix.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
BIN_PATH="${MACOS_DIR}/KoEnFix"
PLIST_PATH="${CONTENTS_DIR}/Info.plist"
ICON_SRC="${PROJECT_DIR}/Resources/AppIcon.icns"

BUNDLE_ID="com.dave.koen-fix"
LAUNCH_AGENT_DIR="${HOME}/Library/LaunchAgents"
LAUNCH_AGENT_PLIST="${LAUNCH_AGENT_DIR}/${BUNDLE_ID}.plist"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--install | --uninstall | --restart | --status | --test]

Options:
  --install     KoEnFix.app 빌드, 자체 테스트, LaunchAgent 등록 및 실행 (기본값)
  --uninstall   LaunchAgent 해제 및 KoEnFix.app 제거
  --restart     KoEnFix 재시작
  --status      실행 상태 확인
  --test        유닛 테스트(--self-test)만 단독 실행
EOF
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "이 스크립트는 macOS 전용입니다."
  exit 1
fi

run_tests() {
  echo "🧪 KoEnFix 자체 테스트 실행 중..."
  local tmp_bin="/tmp/koen-fix-test-$$"
  swiftc -O "$SRC_FILE" -o "$tmp_bin"
  "$tmp_bin" --self-test
  rm -f "$tmp_bin"
}

build_app() {
  echo "🔨 KoEnFix.app 빌드 중..."
  mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
  if [[ ! -f "$ICON_SRC" ]]; then
    echo "앱 아이콘이 없습니다: ${ICON_SRC}" >&2
    echo "  swift \"${PROJECT_DIR}/scripts/render-app-icon.swift\" 로 만든 뒤 다시 설치하세요." >&2
    exit 1
  fi
  cp "$ICON_SRC" "${RESOURCES_DIR}/AppIcon.icns"

  cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>KoEnFix</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>KoEnFix</string>
    <key>CFBundleDisplayName</key>
    <string>KoEnFix</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

  swiftc -O "$SRC_FILE" -o "$BIN_PATH"
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
  "$BIN_PATH" --self-test
}

install_launch_agent() {
  mkdir -p "$LAUNCH_AGENT_DIR"
  cat > "$LAUNCH_AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${BUNDLE_ID}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${BIN_PATH}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>/tmp/koen-fix.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/koen-fix.err</string>
</dict>
</plist>
EOF

  local uid
  uid="$(id -u)"
  # kickstart keeps the previous launch constraint, so a re-signed binary is
  # killed with "Launch Constraint Violation". Reload the job definition.
  launchctl bootout "gui/${uid}/${BUNDLE_ID}" >/dev/null 2>&1 || true
  launchctl bootout "gui/${uid}" "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1 || true
  sleep 0.4
  launchctl bootstrap "gui/${uid}" "$LAUNCH_AGENT_PLIST"
  echo "✅ KoEnFix 설치 및 실행 완료: ${APP_DIR}"
  echo "   상단 메뉴바의 KoEnFix 아이콘을 확인하세요."
  echo "   (최초 실행 시 '시스템 설정 -> 개인정보 보호 및 보안 -> 손쉬운 사용'에서 KoEnFix 권한을 허용해 주세요.)"
}

uninstall_all() {
  local uid
  uid="$(id -u)"
  launchctl bootout "gui/${uid}/${BUNDLE_ID}" >/dev/null 2>&1 || true
  pkill -x KoEnFix >/dev/null 2>&1 || true
  rm -f "$LAUNCH_AGENT_PLIST"
  rm -rf "$APP_DIR"
  rm -rf "${HOME}/Applications/KoEnFix.app"
  echo "🗑️  KoEnFix 제거 완료."
}

show_status() {
  if pgrep -x KoEnFix >/dev/null 2>&1; then
    echo "🟢 KoEnFix 실행 중 (PID: $(pgrep -x KoEnFix | tr '\n' ' '))"
  else
    echo "⚪ KoEnFix 실행 중이 아님"
  fi
}

ACTION="install"
while (("$#")); do
  case "$1" in
    --install)   ACTION="install"; shift ;;
    --uninstall) ACTION="uninstall"; shift ;;
    --restart)   ACTION="restart"; shift ;;
    --status)    ACTION="status"; shift ;;
    --test)      ACTION="test"; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

case "$ACTION" in
  test)
    run_tests
    ;;
  install)
    build_app
    install_launch_agent
    ;;
  restart)
    uid="$(id -u)"
    launchctl kickstart -k "gui/${uid}/${BUNDLE_ID}"
    show_status
    ;;
  uninstall)
    uninstall_all
    ;;
  status)
    show_status
    ;;
esac
