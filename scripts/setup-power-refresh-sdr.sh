#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== [1/1] 전원 연동 주사율 & sdr-native Governor 데몬 복원 시작 ==="

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

echo "-> 대상 사용자: ${TARGET_USER} (UID: ${TARGET_UID}, HOME: ${TARGET_HOME})"

# 사용자 세션 명령 실행 헬퍼
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

# 의존성 검사 (python3, python3-gi)
if ! python3 -c "import gi; gi.require_version('Gio', '2.0'); from gi.repository import Gio, GLib" >/dev/null 2>&1; then
    echo "[!] python3-gi 패키지가 필요합니다. 설치를 진행합니다..."
    if [ "$EUID" -eq 0 ]; then
        apt-get update -qq && apt-get install -y python3-gi
    else
        echo "[!] 관리자 권한으로 python3-gi를 설치합니다..."
        sudo apt-get update -qq && sudo apt-get install -y python3-gi
    fi
fi

# 1. 대상 디렉토리 생성
USER_BIN_DIR="${TARGET_HOME}/.local/bin"
USER_SYSTEMD_DIR="${TARGET_HOME}/.config/systemd/user"

mkdir -p "${USER_BIN_DIR}"
mkdir -p "${USER_SYSTEMD_DIR}"

# 2. 데몬 스크립트 설치
DAEMON_SRC="${PROJECT_ROOT}/configs/bin/power-refresh-sdr-daemon.py"
DAEMON_DEST="${USER_BIN_DIR}/power-refresh-sdr-daemon.py"

echo "-> 데몬 스크립트 설치: ${DAEMON_DEST}"
install -m 755 "${DAEMON_SRC}" "${DAEMON_DEST}"

# 3. systemd user 서비스 유닛 설치
SERVICE_SRC="${PROJECT_ROOT}/configs/systemd-user/power-refresh-sdr.service"
SERVICE_DEST="${USER_SYSTEMD_DIR}/power-refresh-sdr.service"

echo "-> systemd 사용자 서비스 설치: ${SERVICE_DEST}"
install -m 644 "${SERVICE_SRC}" "${SERVICE_DEST}"

# 소유권 정리 (root로 실행된 경우)
if [ "$EUID" -eq 0 ]; then
    chown "${TARGET_USER}:${TARGET_USER}" "${DAEMON_DEST}"
    chown "${TARGET_USER}:${TARGET_USER}" "${SERVICE_DEST}"
fi

# 4. systemd 사용자 서비스 활성화 및 시작
echo "-> systemd user daemon-reload 및 서비스 활성화..."
run_user_cmd systemctl --user daemon-reload
run_user_cmd systemctl --user enable power-refresh-sdr.service
run_user_cmd systemctl --user restart power-refresh-sdr.service

# 5. 상태 확인
sleep 1
if run_user_cmd systemctl --user is-active --quiet power-refresh-sdr.service; then
    echo "[SUCCESS] power-refresh-sdr.service 데몬이 정상적으로 구동 중입니다."
else
    echo "[WARNING] 서비스가 아직 시작되지 않았거나 준비 중입니다."
    run_user_cmd systemctl --user status power-refresh-sdr.service || true
fi

echo "[SUCCESS] 전원 연동 주사율 & sdr-native 설정 복원 완료!"
