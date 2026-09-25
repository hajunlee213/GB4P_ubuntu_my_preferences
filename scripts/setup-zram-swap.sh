#!/usr/bin/env bash
# ==============================================================================
# scripts/setup-zram-swap.sh
# 갤럭시 북4 프로 zram 압축 스왑 & SSD 수명 보호 설정 스크립트
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== zram 압축 스왑(systemd-zram-generator) 설정 ==="

# root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] 이 스크립트는 root 권한(sudo)으로 실행해야 합니다." >&2
    exit 1
fi

# 1. systemd-zram-generator 패키지 설치 확인
if ! dpkg -s systemd-zram-generator &>/dev/null; then
    echo "-> systemd-zram-generator 패키지 설치 중..."
    apt-get update
    apt-get install -y systemd-zram-generator
else
    echo "[+] systemd-zram-generator 패키지가 이미 설치되어 있습니다."
fi

# 2. 설정 파일 복사
ZRAM_SRC="${PROJECT_ROOT}/configs/zram/zram-generator.conf"
ZRAM_DEST="/etc/systemd/zram-generator.conf"

if [ ! -f "${ZRAM_SRC}" ]; then
    echo "[ERROR] zram 설정 템플릿을 찾을 수 없습니다: ${ZRAM_SRC}" >&2
    exit 1
fi

echo "-> /etc/systemd/zram-generator.conf 설정 파일 복사 (8GB, zstd, prio=100)..."
cp "${ZRAM_SRC}" "${ZRAM_DEST}"
chmod 644 "${ZRAM_DEST}"

# 3. systemd 데몬 리로드 및 zram 스왑 유닛 재시작
echo "-> systemd 데몬 갱신 및 zram 스왑 활성화..."
systemctl daemon-reload

if swapon --show | grep -q "/dev/zram0"; then
    echo "-> 기존 활성 /dev/zram0 스왑 안전 해제 중..."
    swapoff /dev/zram0 2>/dev/null || true
fi

echo "-> zram 서비스 및 스왑 유닛 재기동..."
systemctl restart systemd-zram-setup@zram0.service || true
systemctl restart dev-zram0.swap || true

# 스왑 유닛 활성화 확인
if ! swapon --show | grep -q "/dev/zram0"; then
    swapon /dev/zram0 2>/dev/null || true
fi

echo ""
echo "[+] zram 디바이스 상태:"
zramctl || true
echo ""
echo "[+] 전체 스왑 우선순위 상태:"
swapon --show || true
echo ""
echo "[SUCCESS] zram 압축 스왑 설정이 성공적으로 완료되었습니다."
