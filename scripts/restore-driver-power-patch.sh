#!/usr/bin/env bash
# ==============================================================================
# restore-driver-power-patch.sh - Galaxy Book 4 Pro 드라이버 & 전력 설정 순정 복구
# ==============================================================================

set -euo pipefail

echo "======================================================================"
echo " Galaxy Book 4 Pro 드라이버 패치 및 전력 최적화 순정 롤백"
echo "======================================================================"

# 1. root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] 이 스크립트는 root 권한(sudo)으로 실행해야 합니다." >&2
    exit 1
fi

# 2. GRUB 부트로더 커널 파라미터 복구
GRUB_DEFAULT_FILE="/etc/default/grub"
GRUB_PARAMS=(
    "pcie_aspm.policy=powersupersave"
    "i915.force_probe=!7d55"
    "xe.force_probe=7d55"
)

if [ -f "$GRUB_DEFAULT_FILE" ]; then
    GRUB_CHANGED=false
    for param in "${GRUB_PARAMS[@]}"; do
        if grep -q "$param" "$GRUB_DEFAULT_FILE"; then
            if [ "$GRUB_CHANGED" = false ]; then
                BACKUP_FILE="${GRUB_DEFAULT_FILE}.bak.$(date +%Y%m%d%H%M%S)"
                cp "$GRUB_DEFAULT_FILE" "$BACKUP_FILE"
                echo "[+] 기존 GRUB 백업 파일 생성: $BACKUP_FILE"
                GRUB_CHANGED=true
            fi
            echo "-> GRUB 파라미터 제거: $param"
            sed -i "s| $param||g" "$GRUB_DEFAULT_FILE"
            sed -i "s|$param||g" "$GRUB_DEFAULT_FILE"
        fi
    done

    if [ "$GRUB_CHANGED" = true ]; then
        sed -i 's/  */ /g' "$GRUB_DEFAULT_FILE"
        echo "-> GRUB 부트로더 갱신 (update-grub)..."
        if command -v update-grub &>/dev/null; then
            update-grub
        elif command -v grub-mkconfig &>/dev/null; then
            grub-mkconfig -o /boot/grub/grub.cfg
        fi
        echo "[+] GRUB 순정 파라미터 복구 완료."
    else
        echo "[+] GRUB에 등록된 패치 파라미터가 없습니다."
    fi
fi
echo ""

# 3. Dracut / initramfs 드라이버 강제 로드 설정 제거 및 램디스크 갱신
echo "-> 부팅 램디스크 드라이버 설정 정리..."
RAMDISK_NEED_UPDATE=false

if [ -f /etc/dracut.conf.d/i915.conf ]; then
    rm -f /etc/dracut.conf.d/i915.conf
    echo "[+] 삭제 완료: /etc/dracut.conf.d/i915.conf"
    RAMDISK_NEED_UPDATE=true
fi
if [ -f /etc/dracut.conf.d/gpu-drivers.conf ]; then
    rm -f /etc/dracut.conf.d/gpu-drivers.conf
    echo "[+] 삭제 완료: /etc/dracut.conf.d/gpu-drivers.conf"
    RAMDISK_NEED_UPDATE=true
fi

if [ "$RAMDISK_NEED_UPDATE" = true ]; then
    KERNEL_VER="$(uname -r)"
    if command -v dracut &>/dev/null && [ -d /etc/dracut.conf.d ]; then
        echo "-> Dracut 램디스크 갱신 중..."
        dracut -f "/boot/initrd.img-$KERNEL_VER" "$KERNEL_VER"
    elif command -v update-initramfs &>/dev/null; then
        echo "-> update-initramfs 램디스크 갱신 중..."
        update-initramfs -u
    fi
    echo "[+] 램디스크 초기화 완료."
fi
echo ""

# 4. PowerTOP Auto-Tune 서비스 중지 및 제거
echo "-> PowerTOP auto-tune 서비스 제거..."
if systemctl is-active powertop.service &>/dev/null || systemctl is-enabled powertop.service &>/dev/null; then
    systemctl disable --now powertop.service || true
    echo "[+] powertop.service 중지 및 비활성화 완료."
fi
if [ -f /etc/systemd/system/powertop.service ]; then
    rm -f /etc/systemd/system/powertop.service
    systemctl daemon-reload
    echo "[+] 삭제 완료: /etc/systemd/system/powertop.service"
fi
echo ""

# 5. sysctl NMI Watchdog 설정 원복
echo "-> 커널 NMI Watchdog 설정 원복..."
if [ -f /etc/sysctl.d/99-nmi-watchdog.conf ]; then
    rm -f /etc/sysctl.d/99-nmi-watchdog.conf
    echo "[+] 삭제 완료: /etc/sysctl.d/99-nmi-watchdog.conf"
fi
sysctl -w kernel.nmi_watchdog=1 >/dev/null 2>&1 || true
echo "[+] kernel.nmi_watchdog = 1 (기본값) 복구."
echo ""

# 6. 런타임 PCIe ASPM 정책 기본값 복원
if [ -w /sys/module/pcie_aspm/parameters/policy ]; then
    echo default > /sys/module/pcie_aspm/parameters/policy 2>/dev/null || true
    echo "[+] 런타임 PCIe ASPM 정책을 default로 복원했습니다."
fi
echo ""

echo "======================================================================"
echo " [SUCCESS] 드라이버 및 전력 최적화 순정 롤백이 완료되었습니다!"
echo " 재부팅 시 기본 설정으로 동작합니다:"
echo "     sudo reboot"
echo "======================================================================"
