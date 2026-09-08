#!/usr/bin/env bash
# 1. Unlimited Performance Mode
if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo
echo 100 > /sys/devices/system/cpu/intel_pstate/max_perf_pct

# 데스크탑 알림 (백그라운드 비동기)
(
    USER_NAME="${SUDO_USER:-$USER}"
    USER_ID=$(id -u "$USER_NAME" 2>/dev/null || echo 1000)
    sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" notify-send -i emblem-default "전원 모드: 1. 무제한 성능" "터보 부스트: ON | 클럭 제한: 100%" 2>/dev/null
) &

echo "[적용 완료] 1. 무제한 성능 (터보 ON / 100%)"
