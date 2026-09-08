#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== [4/5] 부팅 시 자동 실행(autostart) 항목 복원 시작 ==="

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

AUTOSTART_DIR="${TARGET_HOME}/.config/autostart"
mkdir -p "${AUTOSTART_DIR}"

# 1. power-options-startup.desktop
SRC_POWER="${PROJECT_ROOT}/configs/autostart/power-options-startup.desktop"
DEST_POWER="${AUTOSTART_DIR}/power-options-startup.desktop"
if [ -f "${SRC_POWER}" ]; then
    echo "-> 부팅 전원 프로필 자동 적용 항목 생성 (${DEST_POWER})..."
    sed "s|__TARGET_HOME__|${TARGET_HOME}|g" "${SRC_POWER}" > "${DEST_POWER}"
    chmod 644 "${DEST_POWER}"
fi

# 2. disable-ht.desktop
SRC_HT="${PROJECT_ROOT}/configs/autostart/disable-ht.desktop"
DEST_HT="${AUTOSTART_DIR}/disable-ht.desktop"
if [ -f "${SRC_HT}" ]; then
    echo "-> 부팅 CPU 토폴로지 자동 적용 항목 생성 (${DEST_HT})..."
    sed "s|__TARGET_HOME__|${TARGET_HOME}|g" "${SRC_HT}" > "${DEST_HT}"
    chmod 644 "${DEST_HT}"
fi

chown -R "${TARGET_USER}:${TARGET_USER}" "${AUTOSTART_DIR}"

echo "[SUCCESS] 부팅 시 자동 실행 설정 완료!"
