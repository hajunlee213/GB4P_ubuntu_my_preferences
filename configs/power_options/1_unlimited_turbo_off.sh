#!/usr/bin/env bash
# ==============================================================================
# Unlimited Base Power Mode (풀파워 베이스 클럭 모드 / 터보 OFF)
# - 터보 부스트 : OFF (순간 피크 발열 및 90°C+ 쓰로틀링 방지)
# - 클럭 제한   : 100% (베이스 클럭 대역 내에서 100% 최대 활용)
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo
echo 100 > /sys/devices/system/cpu/intel_pstate/max_perf_pct

# 데스크탑 알림 (백그라운드 비동기)
(
    USER_NAME="${SUDO_USER:-$USER}"
    USER_ID=$(id -u "$USER_NAME" 2>/dev/null || echo 1000)
    sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" notify-send -i emblem-default "전원 모드: 풀파워 (터보 OFF)" "터보 부스트: OFF | 클럭 제한: 100%" 2>/dev/null
) &

echo "[적용 완료] 풀파워 터보 OFF (터보 OFF / 클럭 100%)"
