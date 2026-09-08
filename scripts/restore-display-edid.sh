#!/usr/bin/env bash
# ==============================================================================
# restore-display-edid.sh - Galaxy Book 4 Pro (GB4P) 디스플레이 설정 순정 복구
# ==============================================================================

set -euo pipefail

echo "======================================================================"
echo " Galaxy Book 4 Pro 디스플레이 커스텀 EDID 제거 및 순정(120Hz) 복구"
echo "======================================================================"

# 1. root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] 이 스크립트는 root 권한(sudo)으로 실행해야 합니다." >&2
    exit 1
fi

# 2. GNOME 디스플레이 모니터 설정 캐시 초기화 (해상도/주사율 충돌 방지)
echo "-> GNOME 디스플레이 설정 캐시(monitors.xml) 초기화..."
for user_home in /home/*; do
    if [ -d "$user_home/.config" ]; then
        if [ -f "$user_home/.config/monitors.xml" ]; then
            rm -f "$user_home/.config/monitors.xml"
            echo "[+] 캐시 삭제: $user_home/.config/monitors.xml"
        fi
    fi
done

if [ -f "/root/.config/monitors.xml" ]; then
    rm -f "/root/.config/monitors.xml"
    echo "[+] 캐시 삭제: /root/.config/monitors.xml"
fi

# 3. Dracut 설정 제거
if [ -f /etc/dracut.conf.d/edid.conf ]; then
    rm -f /etc/dracut.conf.d/edid.conf
    echo "[+] 삭제 완료: /etc/dracut.conf.d/edid.conf"
fi

# 4. initramfs-tools 훅 제거
if [ -f /etc/initramfs-tools/hooks/edid ]; then
    rm -f /etc/initramfs-tools/hooks/edid
    echo "[+] 삭제 완료: /etc/initramfs-tools/hooks/edid"
fi

# 5. 커스텀 펌웨어 바이너리 파일 제거
if [ -f /lib/firmware/edid/gb4p_custom_edid.bin ]; then
    rm -f /lib/firmware/edid/gb4p_custom_edid.bin
    echo "[+] 삭제 완료: /lib/firmware/edid/gb4p_custom_edid.bin"
fi
if [ -f /usr/lib/firmware/edid/gb4p_custom_edid.bin ]; then
    rm -f /usr/lib/firmware/edid/gb4p_custom_edid.bin
    echo "[+] 삭제 완료: /usr/lib/firmware/edid/gb4p_custom_edid.bin"
fi

# 6. GRUB 커널 파라미터 정리
GRUB_DEFAULT_FILE="/etc/default/grub"
GRUB_PARAM="drm.edid_firmware=eDP-1:edid/gb4p_custom_edid.bin"

if [ -f "$GRUB_DEFAULT_FILE" ]; then
    if grep -q "$GRUB_PARAM" "$GRUB_DEFAULT_FILE"; then
        sed -i "s| $GRUB_PARAM||g" "$GRUB_DEFAULT_FILE"
        sed -i "s|$GRUB_PARAM||g" "$GRUB_DEFAULT_FILE"
        echo "[+] $GRUB_DEFAULT_FILE 에서 EDID 파라미터 제거 완료."
    else
        echo "[+] $GRUB_DEFAULT_FILE 에 EDID 파라미터가 없습니다."
    fi
fi

# 7. initramfs 및 GRUB 갱신
KERNEL_VER="$(uname -r)"
if command -v dracut &>/dev/null && [ -d /etc/dracut.conf.d ]; then
    echo "-> Dracut 램디스크 갱신 중..."
    dracut -f "/boot/initrd.img-$KERNEL_VER" "$KERNEL_VER"
elif command -v update-initramfs &>/dev/null; then
    echo "-> update-initramfs 램디스크 갱신 중..."
    update-initramfs -u
fi

echo "-> GRUB 부트로더 갱신 중..."
if command -v update-grub &>/dev/null; then
    update-grub
elif command -v grub-mkconfig &>/dev/null; then
    grub-mkconfig -o /boot/grub/grub.cfg
fi

echo ""
echo "======================================================================"
echo " [SUCCESS] 순정 디스플레이 설정 복구가 완료되었습니다!"
echo " 재부팅하면 기본 출고 상태(120Hz)로 부팅됩니다:"
echo "     sudo reboot"
echo "======================================================================"
