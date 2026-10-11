#!/usr/bin/env bash
# ==============================================================================
# 00. Full Power Session (일시적 풀파워 모드 - 재부팅 시 자동 롤백)
# ==============================================================================
# - 모든 CPU 코어 온라인 활성화
# - 터보 부스트 : ON
# - 클럭 제한   : 80%
# - 하드웨어 팬 : Performance (최대 쿨링)
# - Gnome 모드  : Performance
# * sysfs 메모리 설정이므로 재부팅 시 기존 부팅 설정으로 자동 롤백됩니다.
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

echo "[1/4] 모든 CPU 코어 온라인 활성화, 클럭 캡 해제 및 프로세스 격리 해제 중..."
for f in /sys/devices/system/cpu/cpu*/online; do
    [ -f "$f" ] && echo 1 > "$f" 2>/dev/null
done

# 모든 CPU 클럭 상한선 최대치 복원
for f in /sys/devices/system/cpu/cpu*/cpufreq; do
    [ -f "$f/cpuinfo_max_freq" ] && cat "$f/cpuinfo_max_freq" > "$f/scaling_max_freq" 2>/dev/null || true
done

# cgroups v2 모든 슬라이스 격리 해제
systemctl set-property user.slice AllowedCPUs= 2>/dev/null || true
systemctl set-property user-1000.slice AllowedCPUs= 2>/dev/null || true
systemctl set-property system.slice AllowedCPUs= 2>/dev/null || true
systemctl set-property init.scope AllowedCPUs= 2>/dev/null || true

# 오디오 데몬 및 IRQ 친화도 기본값(전코어) 복원
for proc in pipewire wireplumber pipewire-pulse; do
    for pid in $(pgrep -f "$proc" 2>/dev/null); do
        taskset -cp 0-15 "$pid" 2>/dev/null || true
    done
done
for irq in $(grep -Ei "iwlwifi|snd|sof|audio" /proc/interrupts 2>/dev/null | awk '{print $1}' | tr -d ':'); do
    [ -f "/proc/irq/$irq/smp_affinity_list" ] && echo 0-15 > "/proc/irq/$irq/smp_affinity_list" 2>/dev/null || true
done

echo "[2/4] 터보 부스트 ON 및 클럭 제한 80% 설정 중..."
echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo
echo 80 > /sys/devices/system/cpu/intel_pstate/max_perf_pct

echo "[3/4] Performance(고성능) 모드 적용 중..."
# 삼성 하드웨어 팬 / ACPI 플랫폼 프로필
echo "performance" > /sys/firmware/acpi/platform_profile 2>/dev/null

# CPU 에너지 정책 (EPP)
for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    [ -f "$f" ] && echo "performance" > "$f" 2>/dev/null
done

# Gnome 전원 모드
if command -v powerprofilesctl >/dev/null 2>&1; then
    powerprofilesctl set performance 2>/dev/null || true
fi

# 데스크탑 알림 (백그라운드 비동기)
(
    USER_NAME="${SUDO_USER:-$USER}"
    USER_ID=$(id -u "$USER_NAME" 2>/dev/null || echo 1000)
    sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" notify-send -i emblem-default "전원 모드: 00. 풀 파워" "모든 코어 활성화 | 터보 ON | 클럭 80% | Performance" 2>/dev/null
) &

echo "=========================================="
echo " [적용 완료] 00. 풀 파워 세션"
echo " - 모든 CPU 코어 : 온라인 (전체 가동)"
echo " - 터보 부스트   : ON"
echo " - 클럭 상한선   : 80%"
echo " - 플랫폼/팬모드 : Performance"
echo " * 이번 세션 동안 유지되며 재부팅 시 자동 롤백됩니다."
echo "=========================================="
