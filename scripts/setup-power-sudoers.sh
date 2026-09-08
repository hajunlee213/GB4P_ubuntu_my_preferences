#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== [5/5] 무암호 전원 제어 sudoers 설정 복원 시작 ==="

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

SUDOERS_SRC="${PROJECT_ROOT}/configs/sudoers/poweroptions"
SUDOERS_DEST="/etc/sudoers.d/poweroptions"

if [ ! -f "${SUDOERS_SRC}" ]; then
    echo "[ERROR] sudoers 설정 소스 파일을 찾을 수 없습니다: ${SUDOERS_SRC}" >&2
    exit 1
fi

echo "-> /etc/sudoers.d/poweroptions 파일 생성 (${TARGET_USER} 사용자 권한 부여)..."
mkdir -p /etc/sudoers.d
sed -e "s|__TARGET_USER__|${TARGET_USER}|g" -e "s|__TARGET_HOME__|${TARGET_HOME}|g" "${SUDOERS_SRC}" > "${SUDOERS_DEST}"
chmod 0440 "${SUDOERS_DEST}"

# 문법 검증
if command -v visudo >/dev/null 2>&1; then
    visudo -cf "${SUDOERS_DEST}"
fi

echo "-> 적용된 sudoers 설정:"
cat "${SUDOERS_DEST}"

echo "[SUCCESS] sudoers 무암호 권한 설정 완료!"
