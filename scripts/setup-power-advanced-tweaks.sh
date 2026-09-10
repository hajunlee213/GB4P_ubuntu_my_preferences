#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== [6/6] 전력 최적화 고급 튜닝(커서, Wi-Fi, 패키지킷 마스킹, 하드웨어 힌트) 복원 시작 ==="

# root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] 이 스크립트는 root 권한(sudo)으로 실행해야 합니다." >&2
    exit 1
fi

TARGET_USER="${SUDO_USER:-$USER}"
if [ "$TARGET_USER" = "root" ]; then
    TARGET_USER="$(who | awk '{print $1}' | head -n 1)"
    [ -z "$TARGET_USER" ] && TARGET_USER="hajun"
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
USER_ID="$(id -u "$TARGET_USER" 2>/dev/null || echo 1000)"

# 1. 커서 깜빡임 차단 (GPU RC6 및 PSR2 딥슬립 유지)
echo "-> GNOME 및 터미널 커서 깜빡임 비활성화 (PSR2 딥슬립 유지)..."
if [ -d "/run/user/$USER_ID" ]; then
    sudo -u "$TARGET_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" gsettings set org.gnome.desktop.interface cursor-blink false 2>/dev/null || true
    sudo -u "$TARGET_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" dconf write /org/gnome/Ptyxis/cursor-blink-mode "'off'" 2>/dev/null || true
fi

# 2. 백그라운드 패키지 데몬 마스킹 (불필요한 CPU 웨이크업 차단)
echo "-> PackageKit 및 GNOME Software 백그라운드 서비스 마스킹..."
systemctl stop packagekit.service packagekit-offline-update.service 2>/dev/null || true
systemctl mask packagekit.service packagekit-offline-update.service 2>/dev/null || true

if [ -d "/run/user/$USER_ID" ]; then
    sudo -u "$TARGET_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" systemctl --user stop gnome-software.service 2>/dev/null || true
    sudo -u "$TARGET_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" systemctl --user mask gnome-software.service 2>/dev/null || true
    sudo -u "$TARGET_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" gsettings set org.gnome.software download-updates false 2>/dev/null || true
    sudo -u "$TARGET_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" gsettings set org.gnome.software allow-updates false 2>/dev/null || true
fi

# 3. Intel 하드웨어 Workload Type Hints 활성화
echo "-> 인텔 메테오레이크 Workload Type Hints 활성화..."
if [ -f /sys/devices/pci0000:00/0000:00:04.0/workload_hint/workload_hint_enable ]; then
    echo 1 > /sys/devices/pci0000:00/0000:00:04.0/workload_hint/workload_hint_enable 2>/dev/null || true
fi

# 4. Intel Wi-Fi 모듈 절전 파라미터 등록 (/etc/modprobe.d/iwlwifi.conf)
echo "-> Intel Wi-Fi 절전 파라미터 등록 (/etc/modprobe.d/iwlwifi.conf)..."
if [ -f "${PROJECT_ROOT}/configs/modprobe/iwlwifi.conf" ]; then
    cp "${PROJECT_ROOT}/configs/modprobe/iwlwifi.conf" /etc/modprobe.d/iwlwifi.conf
fi

echo "[SUCCESS] 전력 최적화 고급 튜닝 복원 완료!"
