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
# 3. 코어 토폴로지 유지 (AC/DC 공통)
# - P코어 HT (CPU 2, 4, 5, 7) 및 P코어 중앙 (CPU 3, Dark Silicon 완충존): OFF 유지
# - E코어 Cluster 0 (CPU 8~11, P코어 인접): 발열 분산을 위해 항상 OFF
# - E코어 Cluster 1 (CPU 12~15, 다이 외곽): 항상 ON
# ------------------------------------------------------------------------------
for c in 2 3 4 5 7; do
    echo 0 > /sys/devices/system/cpu/cpu$c/online 2>/dev/null
done
for c in 8 9 10 11; do
    echo 0 > /sys/devices/system/cpu/cpu$c/online 2>/dev/null
done
for c in 12 13 14 15; do
    echo 1 > /sys/devices/system/cpu/cpu$c/online 2>/dev/null
done

# ------------------------------------------------------------------------------
# 4. AC / DC 모드별 정책 분기
# ------------------------------------------------------------------------------
if [ "$IS_AC" -eq 1 ]; then
    # ==========================================
    # [AC 전원 연결 모드]
    # - CPU: 2번 밸런스 터보 (터보 ON / 65% 제한)
    # - 삼성 팬모드: Balanced
    # - GNOME 전원: Balanced
    # ==========================================
    echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null
    echo 65 > /sys/devices/system/cpu/intel_pstate/max_perf_pct 2>/dev/null
    echo "balanced" > /sys/firmware/acpi/platform_profile 2>/dev/null
    powerprofilesctl set balanced 2>/dev/null || true

    TITLE="전원 연결 (AC 모드)"
    BODY="Gnome: Balanced | 2번 밸런스 터보 (65%) 적용"
    ICON="battery-charging"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Applied AC Mode: Balanced (Turbo ON / 65%)"
else
    # ==========================================
    # [DC 배터리 모드]
    # - CPU: 1번 풀파워 터보 OFF (터보 OFF / 100% 클럭)
    # - 삼성 팬모드: Balanced (적극적 쿨링으로 발열 누적 방지)
    # - GNOME 전원: Balanced
    # ==========================================
    echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null
    echo 100 > /sys/devices/system/cpu/intel_pstate/max_perf_pct 2>/dev/null
    echo "balanced" > /sys/firmware/acpi/platform_profile 2>/dev/null
    powerprofilesctl set balanced 2>/dev/null || true

    TITLE="배터리 사용 (DC 모드)"
    BODY="Gnome: Balanced | 풀파워 터보 OFF (100%) 적용"
    ICON="battery-low"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Applied DC Mode: Balanced (Turbo OFF / 100%)"
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
