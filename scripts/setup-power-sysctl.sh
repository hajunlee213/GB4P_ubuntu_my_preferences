#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== [1/5] SSD 전력 소모 절감 sysctl 설정 복원 시작 ==="

# root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] 이 스크립트는 root 권한(sudo)으로 실행해야 합니다." >&2
    exit 1
fi

SYSCTL_SRC="${PROJECT_ROOT}/configs/sysctl/99-ssd-power-saving.conf"
SYSCTL_DEST="/etc/sysctl.d/99-ssd-power-saving.conf"

if [ ! -f "${SYSCTL_SRC}" ]; then
    echo "[ERROR] sysctl 설정 파일을 찾을 수 없습니다: ${SYSCTL_SRC}" >&2
    exit 1
fi

echo "-> /etc/sysctl.d/ 디렉토리 생성 및 설정 파일 복사..."
mkdir -p /etc/sysctl.d
cp "${SYSCTL_SRC}" "${SYSCTL_DEST}"
chmod 644 "${SYSCTL_DEST}"

echo "-> 커널 파라미터 즉시 적용..."
sysctl -p "${SYSCTL_DEST}"

echo "-> 적용된 sysctl 설정 확인:"
sysctl vm.dirty_writeback_centisecs vm.dirty_expire_centisecs vm.laptop_mode

echo "[SUCCESS] SSD 전력 절감 sysctl 설정 완료! (디스크 깨움 주기: 60초)"
