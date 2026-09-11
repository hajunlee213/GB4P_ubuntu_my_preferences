#!/usr/bin/env bash
# ==============================================================================
# Check Current Power & CPU Status (현재 상태 점검)
# ==============================================================================

echo "=========================================="
echo "         현재 전원 / CPU 상태 점검"
echo "=========================================="

NO_TURBO=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null)
MAX_PERF=$(cat /sys/devices/system/cpu/intel_pstate/max_perf_pct 2>/dev/null)
PLATFORM_PROF=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null)
EPP=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)

if [ "$NO_TURBO" = "0" ]; then
    TURBO_STAT="ON (사용 중)"
else
    TURBO_STAT="OFF (차단됨)"
fi

ONLINE_CORES=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null)

echo " * 활성 CPU 코어 : ${ONLINE_CORES}개 온라인"
echo " * 터보 부스트   : $TURBO_STAT"
echo " * 클럭 상한선   : ${MAX_PERF}%"
echo " * 에너지 정책   : ${EPP} (EPP)"
echo " * 삼성 팬모드   : ${PLATFORM_PROF}"
echo "------------------------------------------"
echo " [사용 가능한 모드 목록]"
echo " 0) 00_Full_Power.sh          : 전코어 ON / 터보 ON / 80% / Performance (임시)"
echo " 1) 1_unlimited_turbo_on.sh   : 터보 ON  / 클럭 100% (풀파워 터보 ON)"
echo " 2) 1_unlimited_turbo_off.sh  : 터보 OFF / 클럭 100% (풀파워 터보 OFF)"
echo " 3) 2_balanced_turbo_on.sh    : 터보 ON  / 클럭  65% (밸런스 터보)"
echo " 4) 3_balanced_turbo_off.sh   : 터보 OFF / 클럭  80% (밸런스 절전)"
echo " 5) 4_powersave_turbo_off.sh  : 터보 OFF / 클럭  50% (최대 절약)"
echo " 6) custom_limit.sh           : 직접 수치 입력 (대화형)"
echo "------------------------------------------"
echo " [실시간 CPU 코어별 클럭 (MHz)]"
grep "cpu MHz" /proc/cpuinfo | awk '{printf " Core %2d : %6.1f MHz\n", NR-1, $4}'
echo "------------------------------------------"
echo " [주요 온도]"
paste <(cat /sys/class/thermal/thermal_zone*/type 2>/dev/null) <(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null) | awk '{printf " %-15s : %.1f°C\n", $1, $2/1000}' | grep -E 'x86|TCPU|acpitz'
echo "=========================================="
read -p "엔터(Enter) 키를 누르면 닫힙니다..."
