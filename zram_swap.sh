#!/usr/bin/env bash
# ==============================================================================
# zram_swap.sh
# Galaxy Book 4 Pro (GB4P) zram 압축 스왑 & SSD 수명 보호 원클릭 복원 스크립트
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================================="
echo " Galaxy Book 4 Pro (GB4P) zram 압축 스왑 & SSD 수명 보호 복원"
echo " (zram_swap: 8GB zstd 압축 스왑, 우선순위 100)"
echo "========================================================="

# root 권한 확인 및 자동 승격
if [ "$EUID" -ne 0 ]; then
    echo "[!] 관리자 권한이 필요합니다. sudo 로 재실행합니다..."
    exec sudo bash "$0" "$@"
fi

# 롤백 옵션 (--restore 또는 --uninstall) 처리
if [ "${1:-}" = "--restore" ] || [ "${1:-}" = "--uninstall" ]; then
    bash "${SCRIPT_DIR}/scripts/restore-zram-swap.sh"
    exit 0
fi

# 1. zram 압축 스왑 설정 적용
bash "${SCRIPT_DIR}/scripts/setup-zram-swap.sh"

echo ""
echo "========================================================="
echo " [SUCCESS] zram 압축 스왑 복원이 완료되었습니다!"
echo "========================================================="
echo " 1. /etc/systemd/zram-generator.conf:"
echo "    - zram0 크기: 8192 MB (RAM 16GB의 50%)"
echo "    - 압축 알고리즘: zstd (고압축률 & 초저지연)"
echo "    - 스왑 우선순위: 100 (디스크 스왑 /swap.img -1 대비 최우선)"
echo " 2. 핵심 최적화 효과:"
echo "    - NVMe SSD 스왑 쓰기 마모(TBW 소모) 방지 및 SSD 수명 보호"
echo "    - 메모리 부족 시 NVMe I/O 병목 프리징(Thrashing) 원천 차단"
echo "    - 기존 디스크 스왑(/swap.img)은 zram 소진 시 최후의 후방 지원으로 유지"
echo "========================================================="
echo ""
echo " 🔍 적용 상태 확인 명령어:"
echo "    - zram 디바이스 확인: zramctl"
echo "    - 전체 스왑 상태 확인: swapon --show"
echo ""
echo " 🔄 순정 롤백 명령어:"
echo "    - sudo ./zram_swap.sh --restore"
echo "========================================================="
