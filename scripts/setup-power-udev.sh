#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== [3/5] AC/DC 전원 자동 전환 udev 룰 복원 시작 ==="

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

UDEV_RULE_SRC="${PROJECT_ROOT}/configs/udev/99-power-profile-switch.rules"
UDEV_RULE_DEST="/etc/udev/rules.d/99-power-profile-switch.rules"

if [ ! -f "${UDEV_RULE_SRC}" ]; then
    echo "[ERROR] udev 룰 소스 파일을 찾을 수 없습니다: ${UDEV_RULE_SRC}" >&2
    exit 1
fi

echo "-> /etc/udev/rules.d 디렉토리에 룰 생성 (사용자 홈 경로 반영)..."
mkdir -p /etc/udev/rules.d
sed "s|__TARGET_HOME__|${TARGET_HOME}|g" "${UDEV_RULE_SRC}" > "${UDEV_RULE_DEST}"
chmod 644 "${UDEV_RULE_DEST}"

echo "-> 적용된 udev 룰:"
cat "${UDEV_RULE_DEST}"

echo "-> udev 룰 리로드..."
udevadm control --reload-rules
udevadm trigger --subsystem-match=power_supply || true

echo "[SUCCESS] AC/DC 전원 감지 udev 룰 복원 완료!"
