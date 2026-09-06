#!/usr/bin/env bash
set -euo pipefail

echo "=== [3/3] GNOME 터치패드 사용자 환경설정 복원 시작 ==="

# gsettings 실행 헬퍼 (sudo 실행 시 실제 사용자 컨텍스트로 실행)
run_gsettings() {
    local schema="$1"
    local key="$2"
    local value="$3"

    if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
        local user_id
        user_id="$(id -u "${SUDO_USER}")"
        # DBUS 세션 버스 주소 환경 변수 설정 후 su로 실행
        sudo -u "${SUDO_USER}" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${user_id}/bus" gsettings set "${schema}" "${key}" "${value}" 2>/dev/null || \
        sudo -u "${SUDO_USER}" gsettings set "${schema}" "${key}" "${value}" 2>/dev/null || true
    else
        gsettings set "${schema}" "${key}" "${value}" 2>/dev/null || true
    fi
}

SCHEMA="org.gnome.desktop.peripherals.touchpad"

echo "-> 터치패드 탭하여 클릭 (tap-to-click) 활성화..."
run_gsettings "${SCHEMA}" tap-to-click true

echo "-> 타이핑 중 터치패드 비활성화 (disable-while-typing) 활성화..."
run_gsettings "${SCHEMA}" disable-while-typing true

echo "-> 두 손가락 자연스러운 스크롤 (natural-scroll) 활성화..."
run_gsettings "${SCHEMA}" natural-scroll true

echo "-> 두 손가락 스크롤 (two-finger-scrolling-enabled) 활성화..."
run_gsettings "${SCHEMA}" two-finger-scrolling-enabled true

echo "-> 탭 앤 드래그 (tap-and-drag) 활성화..."
run_gsettings "${SCHEMA}" tap-and-drag true

echo "[SUCCESS] GNOME 터치패드 설정 적용 완료!"
