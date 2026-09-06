#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== [1/3] 터치패드 팜리젝션 & DWT 설정 복원 시작 ==="

# root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] 이 스크립트는 root 권한(sudo)으로 실행해야 합니다." >&2
    exit 1
fi

QUIRKS_SRC="${PROJECT_ROOT}/configs/libinput/local-overrides.quirks"
QUIRKS_DEST="/etc/libinput/local-overrides.quirks"

if [ ! -f "${QUIRKS_SRC}" ]; then
    echo "[ERROR] quirks 설정 파일을 찾을 수 없습니다: ${QUIRKS_SRC}" >&2
    exit 1
fi

echo "-> /etc/libinput 디렉토리 생성 및 설정 파일 복사..."
mkdir -p /etc/libinput
cp "${QUIRKS_SRC}" "${QUIRKS_DEST}"
chmod 644 "${QUIRKS_DEST}"

echo "-> 적용된 quirks 파일:"
cat "${QUIRKS_DEST}"

echo "[SUCCESS] 터치패드 quirks 설정 완료!"
echo "참고: libinput 설정은 새 세션 시작 시 또는 터치패드 재연결 시 즉시 적용됩니다."
