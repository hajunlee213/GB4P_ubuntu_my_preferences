#!/usr/bin/env bash
# ==============================================================================
# Custom Clock & Turbo Limit (사용자 지정 클럭 제한 대화형 스크립트)
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

clear
echo "=================================================="
echo "      CPU 클럭 제한 & 터보 부스트 커스텀 설정"
echo "=================================================="

# 현재 상태 읽기
CUR_NO_TURBO=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null)
CUR_MAX_PERF=$(cat /sys/devices/system/cpu/intel_pstate/max_perf_pct 2>/dev/null)

if [ "$CUR_NO_TURBO" = "0" ]; then
    CUR_TURBO_TXT="ON (활성화)"
else
    CUR_TURBO_TXT="OFF (차단됨)"
fi

echo " * 현재 터보 부스트 : $CUR_TURBO_TXT"
echo " * 현재 클럭 상한선 : ${CUR_MAX_PERF}%"
echo "--------------------------------------------------"

# 1. 클럭 제한 백분율 입력 받기
while true; do
    read -p "▶ 원하는 최대 클럭 제한 (%)을 입력하세요 [10 ~ 100] (엔터 = 현재 ${CUR_MAX_PERF}%): " USER_PERF < /dev/tty
    
    # 엔터만 친 경우 현재값 유지
    if [ -z "$USER_PERF" ]; then
        USER_PERF="$CUR_MAX_PERF"
        break
    fi

    # 숫자 유효성 검사 (10 ~ 100)
    if [[ "$USER_PERF" =~ ^[0-9]+$ ]] && [ "$USER_PERF" -ge 10 ] && [ "$USER_PERF" -le 100 ]; then
        break
    else
        echo " ⚠️  10에서 100 사이의 숫자를 입력해 주세요."
    fi
done

# 2. 터보 부스트 여부 입력 받기
echo ""
echo "▶ 터보 부스트(Turbo Boost) 설정:"
echo "   1) 터보 부스트 ON  (단일 코어 순간 가속 허용)"
echo "   2) 터보 부스트 OFF (발열 억제 / 기본 클럭 이내로 제한)"
read -p "선택 [1 또는 2] (엔터 = 1번 ON): " TURBO_CHOICE < /dev/tty

if [ "$TURBO_CHOICE" = "2" ]; then
    NEW_NO_TURBO=1
    TURBO_NAME="OFF"
    EPP_VAL="balance_power"
else
    NEW_NO_TURBO=0
    TURBO_NAME="ON"
    EPP_VAL="balance_performance"
fi

# 3. 설정 적용
echo ""
echo "--------------------------------------------------"
echo "설정을 적용 중입니다..."

echo "$NEW_NO_TURBO" > /sys/devices/system/cpu/intel_pstate/no_turbo
echo "$USER_PERF" > /sys/devices/system/cpu/intel_pstate/max_perf_pct

for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    [ -f "$f" ] && echo "$EPP_VAL" > "$f" 2>/dev/null
done

# 데스크탑 GUI 알림
if command -v notify-send >/dev/null 2>&1; then
    USER_NAME="${SUDO_USER:-$USER}"
    USER_ID=$(id -u "$USER_NAME" 2>/dev/null || echo 1000)
    sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" notify-send -i emblem-default "전원 모드: 커스텀 설정 완료" "터보 부스트: $TURBO_NAME | 클럭 제한: ${USER_PERF}%" 2>/dev/null || true
fi

echo "=================================================="
echo " [적용 완료] 커스텀 전원 설정"
echo " - 터보 부스트 : $TURBO_NAME"
echo " - 클럭 제한   : ${USER_PERF}%"
echo "=================================================="
echo ""
read -p "엔터(Enter) 키를 누르면 종료됩니다..." < /dev/tty
