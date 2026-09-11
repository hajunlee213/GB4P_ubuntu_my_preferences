#!/usr/bin/env bash
# 2. Balanced Turbo Mode
if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo
for f in /sys/devices/system/cpu/cpu*/cpufreq; do
    [ -f "$f/cpuinfo_max_freq" ] && cat "$f/cpuinfo_max_freq" > "$f/scaling_max_freq" 2>/dev/null || true
done
echo 65 > /sys/devices/system/cpu/intel_pstate/max_perf_pct
for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    [ -f "$f" ] && echo "balance_performance" > "$f" 2>/dev/null || true
done

# 데스크탑 알림 (백그라운드 비동기)
(
    USER_NAME="${SUDO_USER:-$USER}"
    USER_ID=$(id -u "$USER_NAME" 2>/dev/null || echo 1000)
    sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" notify-send -i emblem-default "전원 모드: 2. 밸런스 터보" "터보 부스트: ON | 클럭 제한: 65%" 2>/dev/null
) &

echo "[적용 완료] 2. 밸런스 터보 (터보 ON / 65%)"
