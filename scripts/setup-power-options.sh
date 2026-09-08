#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== [2/5] 전원 관리 스크립트 및 CPU 토폴로지 제어 도구 복원 시작 ==="

# root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] 이 스크립트는 root 권한(sudo)으로 실행해야 합니다." >&2
    exit 1
fi

TARGET_USER="${SUDO_USER:-$USER}"
if [ "$TARGET_USER" = "root" ]; then
    TARGET_USER="$(who | awk '{print $1}' | head -n 1)"
    [ -z "$TARGET_USER" ] && TARGET_USER="hajun"
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

echo "-> 대상 사용자: ${TARGET_USER} (홈 디렉토리: ${TARGET_HOME})"

# 1. OneClickScripts/PowerOptions 복원
POWER_OPTIONS_SRC="${PROJECT_ROOT}/configs/power_options"
POWER_OPTIONS_DEST="${TARGET_HOME}/Desktop/OneClickScripts/PowerOptions"

echo "-> 바탕화면 원클릭 전원 도구 복원 (${POWER_OPTIONS_DEST})..."
mkdir -p "${POWER_OPTIONS_DEST}"
cp -a "${POWER_OPTIONS_SRC}/"* "${POWER_OPTIONS_DEST}/"
chmod +x "${POWER_OPTIONS_DEST}/"*.sh
chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/Desktop/OneClickScripts"

# 2. ~/.local/bin/disable-ht.sh 복원
DISABLE_HT_SRC="${PROJECT_ROOT}/configs/bin/disable-ht.sh"
DISABLE_HT_DEST="${TARGET_HOME}/.local/bin/disable-ht.sh"

echo "-> CPU 토폴로지 제어 스크립트 복원 (${DISABLE_HT_DEST})..."
mkdir -p "${TARGET_HOME}/.local/bin"
cp "${DISABLE_HT_SRC}" "${DISABLE_HT_DEST}"
chmod +x "${DISABLE_HT_DEST}"
chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.local/bin"

echo "[SUCCESS] 전원 관리 및 CPU 토폴로지 스크립트 복원 완료!"
