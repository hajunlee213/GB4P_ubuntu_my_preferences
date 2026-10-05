#!/usr/bin/env bash
# ==============================================================================
# scripts/restore-zram-swap.sh
# 갤럭시 북4 프로 zram 설정 순정 원복(롤백) 스크립트
# ==============================================================================
set -euo pipefail

echo "======================================================================"
echo " Galaxy Book 4 Pro zram 압축 스왑 순정 롤백"
echo "======================================================================"

# root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] 이 스크립트는 root 권한(sudo)으로 실행해야 합니다." >&2
    exit 1
fi

# 1. zram 스왑 해제
if swapon --show | grep -q "/dev/zram0"; then
    echo "-> /dev/zram0 스왑 해제 중..."
    swapoff /dev/zram0 2>/dev/null || true
fi

# 2. 관련 systemd 서비스 및 스왑 유닛 중지
echo "-> zram systemd 유닛 중지 중..."
systemctl stop dev-zram0.swap 2>/dev/null || true
systemctl stop systemd-zram-setup@zram0.service 2>/dev/null || true

# 3. 설정 파일 제거
ZRAM_CONF="/etc/systemd/zram-generator.conf"
if [ -f "${ZRAM_CONF}" ]; then
    rm -f "${ZRAM_CONF}"
    echo "[+] 삭제 완료: ${ZRAM_CONF}"
fi

# 4. systemd 데몬 갱신 (유닛 동적 생성 해제)
echo "-> systemd 데몬 갱신..."
systemctl daemon-reload

# 5. zram 블록 디바이스 리셋
if [ -b /dev/zram0 ]; then
    echo "-> /dev/zram0 디바이스 리셋..."
    zramctl --reset /dev/zram0 2>/dev/null || true
fi

# 6. systemd-zram-generator 패키지 제거 (선택적 정리)
if dpkg -s systemd-zram-generator &>/dev/null; then
    echo "-> systemd-zram-generator 패키지 삭제 중..."
    apt-get remove -y systemd-zram-generator
fi

# 7. sysctl zram 커널 파라미터 순정 기본값 복구
for conf in "/etc/sysctl.d/99-zram.conf" "/etc/sysctl.d/99-vm-zram.conf"; do
    if [ -f "${conf}" ]; then
        rm -f "${conf}"
        echo "[+] 삭제 완료: ${conf}"
    fi
done

sysctl -w vm.swappiness=60 >/dev/null 2>&1 || true
sysctl -w vm.page-cluster=3 >/dev/null 2>&1 || true
sysctl -w vm.watermark_boost_factor=15000 >/dev/null 2>&1 || true
sysctl -w vm.watermark_scale_factor=10 >/dev/null 2>&1 || true
echo "[+] 커널 파라미터 우분투 순정 기본값 복구 완료 (swappiness=60, page-cluster=3, watermark_boost=15000, watermark_scale=10)."

echo ""
echo "[+] 현재 스왑 상태 확인:"
swapon --show || true
echo ""
echo "[+] 현재 커널 파라미터 확인:"
sysctl vm.swappiness vm.page-cluster vm.watermark_boost_factor vm.watermark_scale_factor || true
echo ""
echo "======================================================================"
echo " [SUCCESS] zram 스왑 및 커널 파라미터 롤백이 완료되어 순정 상태로 복구되었습니다."
echo "======================================================================"
