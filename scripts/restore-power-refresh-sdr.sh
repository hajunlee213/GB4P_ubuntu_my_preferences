#!/usr/bin/env bash
set -euo pipefail

echo "=== 전원 연동 주사율 & sdr-native Governor 설정 원상 복구(롤백) 시작 ==="

# 대상 사용자 식별
if [ "$EUID" -eq 0 ]; then
    TARGET_USER="${SUDO_USER:-$USER}"
    if [ "$TARGET_USER" = "root" ]; then
        TARGET_USER="$(who | awk '{print $1}' | head -n 1)"
        [ -z "$TARGET_USER" ] && TARGET_USER="hajun"
    fi
else
    TARGET_USER="$USER"
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_UID="$(id -u "$TARGET_USER")"

run_user_cmd() {
    if [ "$EUID" -eq 0 ]; then
        sudo -u "${TARGET_USER}" \
            XDG_RUNTIME_DIR="/run/user/${TARGET_UID}" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus" \
            "$@"
    else
        "$@"
    fi
}

USER_BIN_DIR="${TARGET_HOME}/.local/bin"
USER_SYSTEMD_DIR="${TARGET_HOME}/.config/systemd/user"
DAEMON_DEST="${USER_BIN_DIR}/power-refresh-sdr-daemon.py"
SERVICE_DEST="${USER_SYSTEMD_DIR}/power-refresh-sdr.service"

echo "-> power-refresh-sdr.service 서비스 중지 및 비활성화..."
run_user_cmd systemctl --user stop power-refresh-sdr.service 2>/dev/null || true
run_user_cmd systemctl --user disable power-refresh-sdr.service 2>/dev/null || true

if [ -f "${SERVICE_DEST}" ]; then
    echo "-> 서비스 파일 제거: ${SERVICE_DEST}"
    rm -f "${SERVICE_DEST}"
fi

if [ -f "${DAEMON_DEST}" ]; then
    echo "-> 데몬 스크립트 제거: ${DAEMON_DEST}"
    rm -f "${DAEMON_DEST}"
fi

echo "-> systemd user daemon-reload 및 상태 정리..."
run_user_cmd systemctl --user daemon-reload 2>/dev/null || true
run_user_cmd systemctl --user reset-failed 2>/dev/null || true

echo "[SUCCESS] 전원 연동 주사율 & sdr-native 설정이 완전히 원상 복구되었습니다."
