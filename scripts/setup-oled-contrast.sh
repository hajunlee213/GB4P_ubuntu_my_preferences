#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== [1/1] OLED 다크모드 대비 완화 (화이트포인트 감소 & 블랙 리프트) 설정 복원 ==="

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

echo "-> 대상 사용자: ${TARGET_USER} (UID: ${TARGET_UID}, HOME: ${TARGET_HOME})"

# 사용자 세션 명령 실행 헬퍼
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

# 1. 필수 의존성 검사 (colord, liblcms2-2, python3-dbus)
for pkg in colord liblcms2-2 python3-dbus; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        echo "[!] 필수 패키지 '$pkg' 가 설치되어 있지 않습니다. 설치를 진행합니다..."
        if [ "$EUID" -eq 0 ]; then
            apt-get update -qq && apt-get install -y "$pkg"
        else
            sudo apt-get update -qq && sudo apt-get install -y "$pkg"
        fi
    fi
done

# 2. 대상 디렉토리 생성
USER_ICC_DIR="${TARGET_HOME}/.local/share/icc"
USER_BIN_DIR="${TARGET_HOME}/.local/bin"

mkdir -p "${USER_ICC_DIR}"
mkdir -p "${USER_BIN_DIR}"

# 3. ICC 프로파일 복사
echo "-> OLED 맞춤형 ICC 프로파일 복사..."
cp -f "${PROJECT_ROOT}/configs/icc/oled_gentle_contrast.icc" "${USER_ICC_DIR}/"
cp -f "${PROJECT_ROOT}/configs/icc/oled_medium_contrast.icc" "${USER_ICC_DIR}/"
cp -f "${PROJECT_ROOT}/configs/icc/oled_pure_black.icc" "${USER_ICC_DIR}/"
chmod 644 "${USER_ICC_DIR}/oled_gentle_contrast.icc" "${USER_ICC_DIR}/oled_medium_contrast.icc" "${USER_ICC_DIR}/oled_pure_black.icc"

# 4. oled-mode CLI 도구 설치
echo "-> oled-mode CLI 도구 설치: ${USER_BIN_DIR}/oled-mode"
install -m 755 "${PROJECT_ROOT}/configs/bin/oled-mode" "${USER_BIN_DIR}/oled-mode"

# 시스템 전역 편의 심볼릭 링크 생성 (루트 권한이 있는 경우)
if [ "$EUID" -eq 0 ]; then
    ln -sf "${USER_BIN_DIR}/oled-mode" /usr/local/bin/oled-mode
elif sudo -n true 2>/dev/null; then
    sudo ln -sf "${USER_BIN_DIR}/oled-mode" /usr/local/bin/oled-mode 2>/dev/null || true
fi

# 소유권 정리 (root로 실행된 경우)
if [ "$EUID" -eq 0 ]; then
    chown "${TARGET_USER}:${TARGET_USER}" \
        "${USER_ICC_DIR}/oled_gentle_contrast.icc" \
        "${USER_ICC_DIR}/oled_medium_contrast.icc" \
        "${USER_ICC_DIR}/oled_pure_black.icc" \
        "${USER_BIN_DIR}/oled-mode"
fi

# 5. colormgr에 프로파일 등록 및 디스플레이 장치에 연결
echo "-> colord 컬러 매니저에 ICC 프로파일 등록..."
run_user_cmd colormgr import-profile "${USER_ICC_DIR}/oled_gentle_contrast.icc" 2>/dev/null || true
run_user_cmd colormgr import-profile "${USER_ICC_DIR}/oled_medium_contrast.icc" 2>/dev/null || true
run_user_cmd colormgr import-profile "${USER_ICC_DIR}/oled_pure_black.icc" 2>/dev/null || true

# 디스플레이 장치 탐색
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

echo "-> 타겟 디스플레이 장치: ${DEV_ID}"

# 프로파일 장치 연결
ID_GENTLE="$(run_user_cmd colormgr find-profile-by-filename "${USER_ICC_DIR}/oled_gentle_contrast.icc" 2>/dev/null | grep "Profile ID:" | awk '{print $3}' || true)"
ID_MEDIUM="$(run_user_cmd colormgr find-profile-by-filename "${USER_ICC_DIR}/oled_medium_contrast.icc" 2>/dev/null | grep "Profile ID:" | awk '{print $3}' || true)"
ID_PURE="$(run_user_cmd colormgr find-profile-by-filename "${USER_ICC_DIR}/oled_pure_black.icc" 2>/dev/null | grep "Profile ID:" | awk '{print $3}' || true)"

if [ -n "$ID_GENTLE" ]; then
    run_user_cmd colormgr device-add-profile "$DEV_ID" "$ID_GENTLE" 2>/dev/null || true
fi
if [ -n "$ID_MEDIUM" ]; then
    run_user_cmd colormgr device-add-profile "$DEV_ID" "$ID_MEDIUM" 2>/dev/null || true
fi
if [ -n "$ID_PURE" ]; then
    run_user_cmd colormgr device-add-profile "$DEV_ID" "$ID_PURE" 2>/dev/null || true
fi

# 6. 기본 프로파일(Gentle Contrast) 즉시 적용
echo "-> 기본 프로파일 (Gentle Contrast) 활성화..."
run_user_cmd "${USER_BIN_DIR}/oled-mode" gentle

echo "[SUCCESS] OLED 다크모드 대비 완화 설정 복원 완료!"
