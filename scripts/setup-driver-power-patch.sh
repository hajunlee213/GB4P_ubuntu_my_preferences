#!/usr/bin/env bash
# ==============================================================================
# setup-driver-power-patch.sh - Galaxy Book 4 Pro 차세대 드라이버 & 전력 최적화
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== [1/5] 필수 패키지 및 인텔 펌웨어 설치 ==="

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] 이 스크립트는 root 권한(sudo)으로 실행해야 합니다." >&2
    exit 1
fi

REQUIRED_PACKAGES=("intel-microcode" "thermald" "intel-opencl-icd" "clinfo" "powertop")
MISSING_PACKAGES=()

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        MISSING_PACKAGES+=("$pkg")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo "-> 누락된 필수 패키지 설치 중: ${MISSING_PACKAGES[*]}..."
    apt-get update -y
    apt-get install -y "${MISSING_PACKAGES[@]}"
else
    echo "[+] 모든 필수 패키지가 이미 설치되어 있습니다: ${REQUIRED_PACKAGES[*]}"
fi

# thermald 서비스 활성화
echo "-> thermald(인텔 써멀 관리 데몬) 서비스 활성화..."
systemctl enable --now thermald
echo "[+] thermald 서비스 활성화 완료."
echo ""

echo "=== [2/5] 부팅 램디스크(Dracut/initramfs) GPU 드라이버 패키징 ==="
DRACUT_CONFIGURED=false
INITRAMFS_CONFIGURED=false

if command -v dracut &>/dev/null && [ -d /etc/dracut.conf.d ]; then
    echo "-> Dracut 환경 감지: /etc/dracut.conf.d/gpu-drivers.conf 복원..."
    mkdir -p /etc/dracut.conf.d
    cp "${PROJECT_ROOT}/configs/dracut/gpu-drivers.conf" /etc/dracut.conf.d/gpu-drivers.conf
    chmod 644 /etc/dracut.conf.d/gpu-drivers.conf
    # 이전 잔존 설정 정리
    if [ -f /etc/dracut.conf.d/i915.conf ]; then
        rm -f /etc/dracut.conf.d/i915.conf
    fi
    DRACUT_CONFIGURED=true
fi

if [ -d /etc/initramfs-tools/modules ] || command -v update-initramfs &>/dev/null; then
    if [ -f /etc/initramfs-tools/modules ]; then
        echo "-> initramfs-tools 모듈 설정 확인..."
        for mod in i915 xe; do
            if ! grep -q "^$mod" /etc/initramfs-tools/modules; then
                echo "$mod" >> /etc/initramfs-tools/modules
                echo "[+] /etc/initramfs-tools/modules 에 $mod 추가."
            fi
        done
        INITRAMFS_CONFIGURED=true
    fi
fi

KERNEL_VER="$(uname -r)"
if [ "$DRACUT_CONFIGURED" = true ]; then
    echo "-> Dracut을 통해 부팅 램디스크 갱신 중 (i915 & xe 드라이버 탑재)..."
    dracut -f "/boot/initrd.img-$KERNEL_VER" "$KERNEL_VER"
    echo "[+] Dracut 램디스크 갱신 완료."
elif [ "$INITRAMFS_CONFIGURED" = true ]; then
    echo "-> update-initramfs를 통해 부팅 램디스크 갱신 중..."
    update-initramfs -u
    echo "[+] initramfs 갱신 완료."
fi
echo ""

echo "=== [3/5] GRUB 부트로더 커널 파라미터 등록 ==="
GRUB_DEFAULT_FILE="/etc/default/grub"
GRUB_PARAMS=(
    "i915.force_probe=!7d55"
    "xe.force_probe=7d55"
    "pcie_aspm.policy=powersupersave"
)

if [ -f "$GRUB_DEFAULT_FILE" ]; then
    GRUB_CHANGED=false
    for param in "${GRUB_PARAMS[@]}"; do
        if ! grep -q "$param" "$GRUB_DEFAULT_FILE"; then
            if [ "$GRUB_CHANGED" = false ]; then
                BACKUP_FILE="${GRUB_DEFAULT_FILE}.bak.$(date +%Y%m%d%H%M%S)"
                cp "$GRUB_DEFAULT_FILE" "$BACKUP_FILE"
                echo "[+] 기존 GRUB 백업 파일 생성: $BACKUP_FILE"
                GRUB_CHANGED=true
            fi
            echo "-> GRUB 파라미터 추가: $param"
            if grep -q "GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_DEFAULT_FILE"; then
                sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $param\"/" "$GRUB_DEFAULT_FILE"
            else
                echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$param\"" >> "$GRUB_DEFAULT_FILE"
            fi
        else
            echo "[+] GRUB 파라미터 이미 등록됨: $param"
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
        echo "[+] GRUB 갱신 완료."
    fi
else
    echo "[!] 경고: $GRUB_DEFAULT_FILE 파일을 찾을 수 없습니다."
fi
echo ""

echo "=== [4/5] PowerTOP Auto-Tune 서비스 등록 ==="
POWERTOP_SERVICE_SRC="${PROJECT_ROOT}/configs/systemd/powertop.service"
POWERTOP_SERVICE_DEST="/etc/systemd/system/powertop.service"

if [ -f "$POWERTOP_SERVICE_SRC" ]; then
    echo "-> PowerTOP auto-tune systemd 유닛 복사..."
    cp "$POWERTOP_SERVICE_SRC" "$POWERTOP_SERVICE_DEST"
    chmod 644 "$POWERTOP_SERVICE_DEST"
    systemctl daemon-reload
    systemctl enable powertop.service
    echo "[+] powertop.service 등록 및 활성화 완료."

    echo "-> 런타임 장치 전력 관리 즉시 최적화 실행 (powertop --auto-tune)..."
    powertop --auto-tune || true
    echo "[+] PowerTOP 런타임 자동 튜닝 완료."
fi
echo ""

echo "=== [5/5] 커널 타이머 인터럽트 절전 (NMI Watchdog) & ASPM 즉시 반영 ==="
SYSCTL_SRC="${PROJECT_ROOT}/configs/sysctl/99-nmi-watchdog.conf"
SYSCTL_DEST="/etc/sysctl.d/99-nmi-watchdog.conf"

if [ -f "$SYSCTL_SRC" ]; then
    echo "-> sysctl NMI watchdog 설정 복사..."
    mkdir -p /etc/sysctl.d
    cp "$SYSCTL_SRC" "$SYSCTL_DEST"
    chmod 644 "$SYSCTL_DEST"
    sysctl -p "$SYSCTL_DEST" >/dev/null 2>&1 || sysctl -w kernel.nmi_watchdog=0 >/dev/null
    echo "[+] kernel.nmi_watchdog = 0 적용 완료."
fi

# 런타임 PCIe ASPM policy 즉시 반영 시도
if [ -w /sys/module/pcie_aspm/parameters/policy ]; then
    echo "-> 런타임 PCIe ASPM 정책 즉시 적용 (powersupersave)..."
    echo powersupersave > /sys/module/pcie_aspm/parameters/policy || true
    echo "[+] 현재 ASPM 정책: $(cat /sys/module/pcie_aspm/parameters/policy 2>/dev/null || echo 'N/A')"
fi
echo ""

echo "[SUCCESS] 드라이버 패치 및 전력 최적화 설정이 성공적으로 완료되었습니다!"
