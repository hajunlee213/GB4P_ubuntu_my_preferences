#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== PAM 지문인식(fprintd) 시도 횟수 및 타임아웃 최적화 ==="

# root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] 이 스크립트는 root 권한(sudo)으로 실행해야 합니다." >&2
    exit 1
fi

PAM_SRC="${PROJECT_ROOT}/configs/pam/fprintd"
PAM_DEST="/usr/share/pam-configs/fprintd"

if [ ! -f "${PAM_SRC}" ]; then
    echo "[ERROR] PAM 설정 템플릿을 찾을 수 없습니다: ${PAM_SRC}" >&2
    exit 1
fi

echo "-> /usr/share/pam-configs/fprintd 업데이트 (max-tries=3, timeout=30)..."
cp "${PAM_SRC}" "${PAM_DEST}"
chmod 644 "${PAM_DEST}"

echo "-> pam-auth-update 실행하여 /etc/pam.d/common-auth 갱신..."
pam-auth-update --package

echo "[SUCCESS] PAM fprintd 설정 완료 (최대 3회 시도, 30초 타임아웃)!"
