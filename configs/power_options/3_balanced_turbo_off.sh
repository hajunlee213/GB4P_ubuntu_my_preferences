#!/usr/bin/env bash
# 3. Balanced Power Mode
if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo
echo 80 > /sys/devices/system/cpu/intel_pstate/max_perf_pct
for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    [ -f "$f" ] && echo "power" > "$f" 2>/dev/null || true
done

# 데스크탑 알림 (백그라운드 비동기)
(
    USER_NAME="${SUDO_USER:-$USER}"
    USER_ID=$(id -u "$USER_NAME" 2>/dev/null || echo 1000)
    sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" notify-send -i emblem-default "전원 모드: 3. 밸런스 절전" "터보 부스트: OFF | 클럭 제한: 80%" 2>/dev/null
) &

echo "[적용 완료] 3. 밸런스 절전 (터보 OFF / 80%)"
