#!/usr/bin/env bash
# ==============================================================================
# setup-display-edid.sh - Galaxy Book 4 Pro (GB4P) EDID 다중 주사율 복원
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== [1/2] 커스텀 EDID 펌웨어 및 부팅 설정 복원 시작 ==="

# 1. root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] 이 스크립트는 root 권한(sudo)으로 실행해야 합니다." >&2
    exit 1
fi

EDID_SRC="${PROJECT_ROOT}/configs/edid/gb4p_custom_edid.bin"
if [ ! -f "${EDID_SRC}" ]; then
    echo "[ERROR] EDID 바이너리 파일을 찾을 수 없습니다: ${EDID_SRC}" >&2
    exit 1
fi

# 2. 펌웨어 디렉토리에 바이너리 복사 (/lib/firmware/edid 및 /usr/lib/firmware/edid)
echo "-> 커스텀 EDID 바이너리 설치 (/lib/firmware/edid/)..."
mkdir -p /lib/firmware/edid
cp "${EDID_SRC}" /lib/firmware/edid/gb4p_custom_edid.bin
chmod 644 /lib/firmware/edid/gb4p_custom_edid.bin

# /usr/lib/firmware/edid 가 별도 디렉토리인 경우에도 동기화
if [ -d /usr/lib/firmware ] && [ ! -L /usr/lib/firmware ]; then
    mkdir -p /usr/lib/firmware/edid
    cp "${EDID_SRC}" /usr/lib/firmware/edid/gb4p_custom_edid.bin
    chmod 644 /usr/lib/firmware/edid/gb4p_custom_edid.bin
fi
echo "[+] EDID 바이너리 복사 완료."

# 3. 램디스크(initramfs) 설정 복원 및 재생성
KERNEL_VER="$(uname -r)"
DRACUT_CONFIGURED=false
INITRAMFS_CONFIGURED=false

# Dracut 환경 감지 및 설정
if command -v dracut &>/dev/null && [ -d /etc/dracut.conf.d ]; then
    echo "-> Dracut 설정 감지: /etc/dracut.conf.d/edid.conf 복원..."
    mkdir -p /etc/dracut.conf.d
    cp "${PROJECT_ROOT}/configs/dracut/edid.conf" /etc/dracut.conf.d/edid.conf
    chmod 644 /etc/dracut.conf.d/edid.conf
    DRACUT_CONFIGURED=true
fi

# initramfs-tools 환경 감지 및 설정
if [ -d /etc/initramfs-tools/hooks ] || command -v update-initramfs &>/dev/null; then
    echo "-> initramfs-tools 설정 감지: /etc/initramfs-tools/hooks/edid 복원..."
    mkdir -p /etc/initramfs-tools/hooks
    cp "${PROJECT_ROOT}/configs/initramfs-tools/edid" /etc/initramfs-tools/hooks/edid
    chmod +x /etc/initramfs-tools/hooks/edid
    INITRAMFS_CONFIGURED=true
fi

# 램디스크 빌드 실행
if [ "$DRACUT_CONFIGURED" = true ]; then
    echo "-> Dracut을 통해 부팅 램디스크 갱신 중..."
    dracut -f "/boot/initrd.img-$KERNEL_VER" "$KERNEL_VER"
elif [ "$INITRAMFS_CONFIGURED" = true ]; then
    echo "-> update-initramfs를 통해 부팅 램디스크 갱신 중..."
    update-initramfs -u
else
    echo "[!] 경고: 감지된 램디스크 빌더가 없습니다. 램디스크 수동 확인이 필요할 수 있습니다."
fi
echo "[+] 부팅 램디스크(Early KMS)에 EDID 바이너리 패키징 완료."

# 4. GRUB 커널 커맨드라인 파라미터 등록
GRUB_DEFAULT_FILE="/etc/default/grub"
GRUB_PARAM="drm.edid_firmware=eDP-1:edid/gb4p_custom_edid.bin"

if [ -f "$GRUB_DEFAULT_FILE" ]; then
    echo "-> GRUB 부트로더 설정 확인 ($GRUB_DEFAULT_FILE)..."
    if ! grep -q "$GRUB_PARAM" "$GRUB_DEFAULT_FILE"; then
        BACKUP_FILE="${GRUB_DEFAULT_FILE}.bak.$(date +%Y%m%d%H%M%S)"
        cp "$GRUB_DEFAULT_FILE" "$BACKUP_FILE"
        echo "[+] 기존 GRUB 설정 백업 생성: $BACKUP_FILE"

        if grep -q "GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_DEFAULT_FILE"; then
            sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $GRUB_PARAM\"/" "$GRUB_DEFAULT_FILE"
            sed -i 's/  */ /g' "$GRUB_DEFAULT_FILE"
        else
            echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB_PARAM\"" >> "$GRUB_DEFAULT_FILE"
        fi
        echo "[+] GRUB 커널 파라미터에 '$GRUB_PARAM' 추가 완료."
    else
        echo "[+] GRUB 커널 파라미터에 '$GRUB_PARAM' 이미 등록되어 있습니다."
    fi

    echo "-> GRUB 부트로더 갱신 (update-grub)..."
    if command -v update-grub &>/dev/null; then
        update-grub
    elif command -v grub-mkconfig &>/dev/null; then
        grub-mkconfig -o /boot/grub/grub.cfg
    fi
    echo "[+] GRUB 갱신 완료."
else
    echo "[!] 경고: $GRUB_DEFAULT_FILE 파일을 찾을 수 없습니다. 부트로더 설정을 수동으로 확인하세요."
fi

echo "[SUCCESS] 디스플레이 커스텀 EDID 설정 완료!"
