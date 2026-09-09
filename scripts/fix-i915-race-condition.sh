#!/usr/bin/env bash
# ==============================================================================
# fix-i915-race-condition.sh - i915 부팅 레이스 컨디션 해결 (Early KMS 패키징)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== [i915 Early KMS] 부팅 레이스 컨디션 방지 설정 시작 ==="

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] 이 스크립트는 root 권한(sudo)으로 실행해야 합니다." >&2
    exit 1
fi

DRACUT_CONFIGURED=false
INITRAMFS_CONFIGURED=false

# 1. Dracut 환경 설정 (Ubuntu 26.04+ 기본)
if command -v dracut &>/dev/null && [ -d /etc/dracut.conf.d ]; then
    echo "-> Dracut 감지: /etc/dracut.conf.d/i915.conf 생성 및 복원..."
    mkdir -p /etc/dracut.conf.d
    if [ -f "${PROJECT_ROOT}/configs/dracut/i915.conf" ]; then
        cp "${PROJECT_ROOT}/configs/dracut/i915.conf" /etc/dracut.conf.d/i915.conf
    else
        echo 'force_drivers+=" i915 "' > /etc/dracut.conf.d/i915.conf
    fi
    chmod 644 /etc/dracut.conf.d/i915.conf
    
    # 이전 불필요한 설정 파일 정리
    if [ -f /etc/dracut.conf.d/gpu-drivers.conf ]; then
        rm -f /etc/dracut.conf.d/gpu-drivers.conf
    fi
    DRACUT_CONFIGURED=true
    echo "[+] Dracut i915 force_drivers 설정 완료."
fi

# 2. initramfs-tools 환경 설정 (Ubuntu 22.04/24.04 레거시 호환)
if [ -d /etc/initramfs-tools/modules ] || command -v update-initramfs &>/dev/null; then
    if [ -f /etc/initramfs-tools/modules ]; then
        echo "-> initramfs-tools 감지: /etc/initramfs-tools/modules 확인..."
        if ! grep -q "^i915" /etc/initramfs-tools/modules; then
            echo "i915" >> /etc/initramfs-tools/modules
            echo "[+] /etc/initramfs-tools/modules 에 i915 모듈 등록."
        else
            echo "[+] /etc/initramfs-tools/modules 에 i915 모듈 이미 존재함."
        fi
        INITRAMFS_CONFIGURED=true
    fi
fi

# 3. 부팅 램디스크(initramfs) 재생성
KERNEL_VER="$(uname -r)"
if [ "$DRACUT_CONFIGURED" = true ]; then
    echo "-> Dracut을 통해 부팅 램디스크 재생성 중 (/boot/initrd.img-$KERNEL_VER)..."
    dracut -f "/boot/initrd.img-$KERNEL_VER" "$KERNEL_VER"
    echo "[+] Dracut 램디스크 재생성 완료 (i915 Early KMS 주입)."
elif [ "$INITRAMFS_CONFIGURED" = true ]; then
    echo "-> update-initramfs를 통해 부팅 램디스크 재생성 중..."
    update-initramfs -u
    echo "[+] initramfs 재생성 완료 (i915 Early KMS 주입)."
else
    echo "[!] 경고: 감지된 램디스크 도구가 없습니다."
fi

echo "[SUCCESS] i915 Early KMS 설정이 완료되었습니다! (부팅 시 GDM과의 타이밍 충돌 원천 차단)"
