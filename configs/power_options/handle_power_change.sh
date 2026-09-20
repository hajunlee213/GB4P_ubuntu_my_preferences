#!/usr/bin/env bash
# ==============================================================================
# AC (충전기) / DC (배터리) 자동 전원 전환 핸들러 (안정화 & 최적화 버전)
# ==============================================================================

# root 권한 자동 승격 (맨 처음 수행)
if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

# ------------------------------------------------------------------------------
# 1. 중복 실행 방지 (flock 기반 파일 락 & 디바운스)
# ------------------------------------------------------------------------------
LOCKFILE="/run/lock/handle_power_change.lock"
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    exit 0
fi

# 하드웨어 sysfs 상태 안정화를 위한 디바운스 대기
sleep 0.3

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------------------------------------------------------
# 2. AC (충전기 연결 여부) 판별
# ------------------------------------------------------------------------------
IS_AC=0
if [ -f "/sys/class/power_supply/ADP1/online" ]; then
    if [ "$(cat /sys/class/power_supply/ADP1/online 2>/dev/null)" = "1" ]; then
        IS_AC=1
    fi
else
    for f in /sys/class/power_supply/*/online; do
        if [ -f "$f" ] && [ "$(cat "$f" 2>/dev/null)" = "1" ]; then
            IS_AC=1
            break
        fi
    done
fi

# ------------------------------------------------------------------------------
# 3. 코어 토폴로지 유지 (E-코어 8개 전용 체제 + P코어 0번 식물인간 격리)
# - P코어 (CPU 1~7): 완전 OFF (하드웨어 오프라인)
# - CPU 0: x86 BSP 커널 제약으로 하드웨어 상주하되, cgroups v2로 작업 할당 차단 -> C10 딥슬립 유지
# - E코어 Cluster 0 & 1 (CPU 8~15, 8개 E코어 전체): 항상 ON (저발열 멀티코어 전담)
# - LP-E 코어 (CPU 16, 17, SoC 타일): 인터커넥트 오버헤드 차단을 위해 항상 OFF
# ------------------------------------------------------------------------------
for c in 1 2 3 4 5 6 7; do
    echo 0 > /sys/devices/system/cpu/cpu$c/online 2>/dev/null || true
done
for c in {8..15}; do
    echo 1 > /sys/devices/system/cpu/cpu$c/online 2>/dev/null || true
done
for c in 16 17; do
    echo 0 > /sys/devices/system/cpu/cpu$c/online 2>/dev/null || true
done

# 사용자 세션 프로세스를 8개 E-코어(8-15)로 제한하여 CPU 0을 식물 상태(C10 슬립)로 유지
systemctl set-property user.slice AllowedCPUs=8-15 2>/dev/null || true
systemctl set-property user-1000.slice AllowedCPUs=8-15 2>/dev/null || true

# ------------------------------------------------------------------------------
# 4. AC / DC 모드별 정책 분기
# ------------------------------------------------------------------------------
if [ "$IS_AC" -eq 1 ]; then
    # ==========================================
    # [AC 전원 연결 모드]
    # - CPU: E-코어 8개 부스트 가동 (터보 ON / 80% 제한 -> E코어 ~3.0GHz * 8개)
    # - 삼성 팬모드: Balanced
    # - GNOME 전원: Balanced
    # - EPP: balance_performance (즉각적인 작업 반응성 유지)
    # ==========================================
    echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null
    for f in /sys/devices/system/cpu/cpu*/cpufreq; do
        [ -f "$f/cpuinfo_max_freq" ] && cat "$f/cpuinfo_max_freq" > "$f/scaling_max_freq" 2>/dev/null || true
    done
    echo 80 > /sys/devices/system/cpu/intel_pstate/max_perf_pct 2>/dev/null
    echo "balanced" > /sys/firmware/acpi/platform_profile 2>/dev/null
    powerprofilesctl set balanced 2>/dev/null || true
    for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        [ -f "$f" ] && echo "balance_performance" > "$f" 2>/dev/null || true
    done
    (
        sleep 0.5
        for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
            [ -f "$f" ] && echo "balance_performance" > "$f" 2>/dev/null || true
        done
    ) &

    TITLE="전원 연결 (AC 모드)"
    BODY="Gnome: Balanced (EPP: bal_perf) | E-코어 부스트 (80% / ~3.0GHz) 적용"
    ICON="battery-charging"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Applied AC Mode: Balanced (E-cores 80% / ~3.0GHz, EPP: balance_performance)"
else
    # ==========================================
    # [DC 배터리 모드]
    # - CPU: E-코어 8개 부스트 가동 (터보 ON / 70% 제한 -> E코어 ~2.5GHz * 8개, 전성비 최적)
    # - 삼성 팬모드: Low-Power (무소음 / 팬 동작 억제)
    # - GNOME 전원: Power Saver
    # - EPP: power (하드웨어 최저 전력 선호도 강제)
    # ==========================================
    echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null
    for f in /sys/devices/system/cpu/cpu*/cpufreq; do
        [ -f "$f/cpuinfo_max_freq" ] && cat "$f/cpuinfo_max_freq" > "$f/scaling_max_freq" 2>/dev/null || true
    done
    echo 70 > /sys/devices/system/cpu/intel_pstate/max_perf_pct 2>/dev/null
    echo "low-power" > /sys/firmware/acpi/platform_profile 2>/dev/null
    powerprofilesctl set power-saver 2>/dev/null || true
    for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        [ -f "$f" ] && echo "power" > "$f" 2>/dev/null || true
    done
    (
        sleep 0.5
        for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
            [ -f "$f" ] && echo "power" > "$f" 2>/dev/null || true
        done
    ) &

    TITLE="배터리 사용 (DC 모드)"
    BODY="Gnome: Power Saver (EPP: power) | E-코어 부스트 (70% / ~2.5GHz) 적용"
    ICON="battery-low"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Applied DC Mode: Power Saver (E-cores 70% / ~2.5GHz, EPP: power)"
fi

# ------------------------------------------------------------------------------
# 5. 안전한 사용자 세션 데스크탑 알림 (백그라운드 비동기)
# ------------------------------------------------------------------------------
(
    USER_NAME="${SUDO_USER:-$USER}"
    if [ "$USER_NAME" = "root" ]; then
        USER_NAME=$(who | awk '{print $1}' | head -n 1)
        [ -z "$USER_NAME" ] && USER_NAME="hajun"
    fi
    USER_ID=$(id -u "$USER_NAME" 2>/dev/null || echo 1000)

    if [ -d "/run/user/$USER_ID" ]; then
        sudo -u "$USER_NAME" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" \
            notify-send -i "$ICON" "$TITLE" "$BODY" 2>/dev/null
    fi
) &
