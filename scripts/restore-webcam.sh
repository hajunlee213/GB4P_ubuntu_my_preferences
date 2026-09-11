#!/usr/bin/env bash
# ==============================================================================
# scripts/restore-webcam.sh
# 갤럭시 북4 프로 웹캠 드라이버 및 Relay 패치 순정 원복(롤백) 스크립트
# ==============================================================================
set -euo pipefail

ACTUAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)

echo "[*] 웹캠 드라이버 및 On-Demand Relay 설정을 순정 상태로 롤백합니다..."

# 1. On-Demand Relay 사용자 서비스 중지 및 비활성화
echo "[1/7] camera-relay 사용자 서비스 비활성화 중..."
if command -v systemctl &>/dev/null; then
    su - "$ACTUAL_USER" -c "systemctl --user stop camera-relay.service && systemctl --user disable camera-relay.service" 2>/dev/null || true
fi
rm -f "${USER_HOME}/.config/systemd/user/camera-relay.service"
if command -v systemctl &>/dev/null; then
    su - "$ACTUAL_USER" -c "systemctl --user daemon-reload" 2>/dev/null || true
fi

# 2. upstream check 서비스 비활성화 및 스크립트 제거
echo "[2/7] ipu-bridge upstream check 서비스 제거 중..."
systemctl stop ipu-bridge-check-upstream.service 2>/dev/null || true
systemctl disable ipu-bridge-check-upstream.service 2>/dev/null || true
rm -f /etc/systemd/system/ipu-bridge-check-upstream.service
rm -f /usr/local/sbin/ipu-bridge-check-upstream.sh
systemctl daemon-reload

# 3. 설치된 바이너리 제거
echo "[3/7] camera-relay 바이너리 제거 중..."
rm -f /usr/local/bin/camera-relay
rm -f /usr/local/bin/camera-relay-monitor

# 4. udev 룰 제거
echo "[4/7] udev 룰 제거 중..."
rm -f /etc/udev/rules.d/70-camera-relay-capabilities.rules
rm -f /etc/udev/rules.d/90-hide-ipu6-v4l2.rules
rm -f /etc/udev/rules.d/99-ipu6.rules
udevadm control --reload-rules
udevadm trigger

# 5. modprobe 및 modules-load 설정 제거
echo "[5/7] 커널 모듈 설정 파일 제거 중..."
rm -f /etc/modprobe.d/99-camera-relay-loopback.conf
rm -f /etc/modprobe.d/ivsc-camera.conf
rm -f /etc/modules-load.d/v4l2loopback.conf
rm -f /etc/modules-load.d/ivsc.conf

# 6. dracut / initramfs-tools 펌웨어 훅 제거
echo "[6/7] initramfs 펌웨어 번들 설정 제거 중..."
NEEDS_INITRAMFS=0
if [ -f /etc/dracut.conf.d/ipu6-firmware.conf ]; then
    rm -f /etc/dracut.conf.d/ipu6-firmware.conf
    NEEDS_INITRAMFS=1
fi
if [ -f /etc/initramfs-tools/hooks/ipu6-firmware ]; then
    rm -f /etc/initramfs-tools/hooks/ipu6-firmware
    NEEDS_INITRAMFS=1
fi

if [ "$NEEDS_INITRAMFS" -eq 1 ]; then
    echo "  -> initramfs 램디스크 갱신 중..."
    if command -v dracut &>/dev/null; then
        dracut -f --quiet || true
    elif command -v update-initramfs &>/dev/null; then
        update-initramfs -u -k all || true
    fi
fi

# 7. DKMS 모듈 제거 (옵션 질문 또는 안내)
echo "[7/7] DKMS 모듈 롤백..."
read -rp "  ipu-bridge-fix 및 ov02c10 DKMS 모듈도 커널에서 제거하시겠습니까? [y/N]: " REMOVE_DKMS
case "$REMOVE_DKMS" in
    [yY]|[yY][eE][sS])
        echo "  -> DKMS 모듈 제거 진행..."
        dkms remove ipu-bridge-fix/1.4 --all 2>/dev/null || true
        dkms remove ov02c10/1.0 --all 2>/dev/null || true
        rm -rf /usr/src/ipu-bridge-fix-1.4 /usr/src/ov02c10-1.0
        depmod -a
        echo "  ✓ DKMS 모듈 제거 완료"
        ;;
    *)
        echo "  -> DKMS 모듈은 보존됩니다."
        ;;
esac

echo ""
echo "========================================================="
echo " [SUCCESS] 웹캠 드라이버 및 Relay 설정이 순정으로 복구되었습니다."
echo " 변경사항을 완전히 적용하려면 재부팅(sudo reboot)을 권장합니다."
echo "========================================================="
