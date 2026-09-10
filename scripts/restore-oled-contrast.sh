#!/usr/bin/env bash
set -euo pipefail

echo "=== OLED 다크모드 대비 완화 설정 원상 복구(롤백) 시작 ==="

# 대상 사용자 식별
if [ "$EUID" -eq 0 ]; then
    TARGET_USER="${SUDO_USER:-$USER}"
    if [ "$TARGET_USER" = "root" ]; then
        TARGET_USER="$(who | awk '{print $1}' | head -n 1)"
        [ -z "$TARGET_USER" ] && TARGET_USER="hajun"
    fi
else
    TARGET_USER="$USER"
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_UID="$(id -u "$TARGET_USER")"

run_user_cmd() {
    if [ "$EUID" -eq 0 ]; then
        sudo -u "${TARGET_USER}" \
            XDG_RUNTIME_DIR="/run/user/${TARGET_UID}" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus" \
            "$@"
    else
        "$@"
    fi
}

USER_ICC_DIR="${TARGET_HOME}/.local/share/icc"
USER_BIN_DIR="${TARGET_HOME}/.local/bin"

# 1. 패널 순정 상태로 프로파일 복원 및 CTM 초기화
if [ -x "${USER_BIN_DIR}/oled-mode" ]; then
    echo "-> oled-mode reset 실행 (패널 순정 상태 복구 및 CTM 초기화)..."
    run_user_cmd "${USER_BIN_DIR}/oled-mode" reset || true
fi

# 2. colormgr 장치에서 등록된 커스텀 프로파일 연결 해제
DEV_ID="$(run_user_cmd python3 -c '
import subprocess
try:
    res = subprocess.run(["colormgr", "get-devices"], capture_output=True, text=True, check=True)
    cur = None
    for line in res.stdout.splitlines():
        line = line.strip()
        if line.startswith("Device ID:"):
            cur = line.split(":", 1)[1].strip()
        elif line.startswith("Type:") and "display" in line.lower():
            if cur:
                print(cur)
                break
except Exception:
    pass
' 2>/dev/null || true)"

[ -z "$DEV_ID" ] && DEV_ID="xrandr-Samsung Display Corp.-0x4188-0x00000000"

for f in oled_high_contrast.icc oled_high_pure_black.icc oled_medium_contrast.icc oled_medium_pure_black.icc oled_low_pure_black.icc oled_gentle_contrast.icc oled_pure_black.icc oled_custom.icc; do
    if [ -f "${USER_ICC_DIR}/$f" ]; then
        PROF_ID="$(run_user_cmd colormgr find-profile-by-filename "${USER_ICC_DIR}/$f" 2>/dev/null | grep "Profile ID:" | awk '{print $3}' || true)"
        if [ -n "$PROF_ID" ]; then
            echo "-> colord 장치 연결 해제: $f ($PROF_ID)"
            run_user_cmd colormgr device-remove-profile "$DEV_ID" "$PROF_ID" 2>/dev/null || true
        fi
        rm -f "${USER_ICC_DIR}/$f"
    fi
done

# 3. CLI 실행 스크립트 제거
if [ -f "${USER_BIN_DIR}/oled-mode" ]; then
    echo "-> CLI 스크립트 제거: ${USER_BIN_DIR}/oled-mode"
    rm -f "${USER_BIN_DIR}/oled-mode"
fi

if [ -L /usr/local/bin/oled-mode ] || [ -f /usr/local/bin/oled-mode ]; then
    echo "-> 시스템 심볼릭 링크 제거: /usr/local/bin/oled-mode"
    if [ "$EUID" -eq 0 ]; then
        rm -f /usr/local/bin/oled-mode
    elif sudo -n true 2>/dev/null; then
        sudo rm -f /usr/local/bin/oled-mode 2>/dev/null || true
    fi
fi

echo "[SUCCESS] OLED 다크모드 대비 완화 설정이 완전히 원상 복구(순정 출하 상태)되었습니다."
