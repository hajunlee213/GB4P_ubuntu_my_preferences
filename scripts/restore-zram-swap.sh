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

# 7. sysctl swappiness 순정 기본값(60) 복구
SYSCTL_DEST="/etc/sysctl.d/99-vm-zram.conf"
if [ -f "${SYSCTL_DEST}" ]; then
    rm -f "${SYSCTL_DEST}"
    echo "[+] 삭제 완료: ${SYSCTL_DEST}"
fi
sysctl -w vm.swappiness=60 >/dev/null 2>&1 || true
echo "[+] vm.swappiness = 60 (우분투 기본값) 복구."

echo ""
echo "[+] 현재 스왑 상태 확인:"
swapon --show || true
echo ""
echo "[+] 현재 swappiness 설정:"
sysctl vm.swappiness || true
echo ""
echo "======================================================================"
echo " [SUCCESS] zram 스왑 및 swappiness 롤백이 완료되어 순정 상태로 복구되었습니다."
echo "======================================================================"
