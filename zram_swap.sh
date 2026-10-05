#!/usr/bin/env bash
# ==============================================================================
# zram_swap.sh
# Galaxy Book 4 Pro (GB4P) zram 압축 스왑 & SSD 수명 보호 원클릭 복원 스크립트
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================================="
echo " Galaxy Book 4 Pro (GB4P) zram 압축 스왑 & SSD 수명 보호 복원"
echo " (zram_swap: 16GB zstd 압축 스왑, 우선순위 100, 커널 파라미터 최적화)"
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
echo "    - zram0 크기: 16384 MB (RAM 16GB의 100% 매핑)"
echo "    - 압축 알고리즘: zstd (고압축률 & 초저지연)"
echo "    - 스왑 우선순위: 100 (디스크 스왑 /swap.img -1 대비 최우선)"
echo " 2. /etc/sysctl.d/99-zram.conf:"
echo "    - vm.swappiness: 150 (zram 압축 메모리 적극 활용 및 파일 캐시 보존)"
echo "    - vm.page-cluster: 0 (단일 페이지 단위 초고속 RAM I/O, 읽기 증폭 제거)"
echo "    - vm.watermark_boost_factor: 0 (kswapd 과잉 회수 방지 및 지연 스파이크 차단)"
echo "    - vm.watermark_scale_factor: 125 (완만하고 안정적인 메모리 워터마크 버퍼 확보)"
echo " 3. 핵심 최적화 효과:"
echo "    - NVMe SSD 스왑 쓰기 마모(TBW 소모) 방지 및 SSD 수명 보호"
echo "    - 메모리 부족 시 NVMe I/O 병목 프리징(Thrashing) 원천 차단"
echo "    - 기존 디스크 스왑(/swap.img)은 zram 소진 시 최후의 후방 지원으로 유지"
echo "========================================================="
echo ""
echo " 🔍 적용 상태 확인 명령어:"
echo "    - zram 디바이스 확인: zramctl"
echo "    - 전체 스왑 상태 확인: swapon --show"
echo "    - 커널 파라미터 확인: sysctl vm.swappiness vm.page-cluster vm.watermark_boost_factor vm.watermark_scale_factor"
echo ""
echo " 🔄 순정 롤백 명령어:"
echo "    - sudo ./zram_swap.sh --restore"
echo "========================================================="
