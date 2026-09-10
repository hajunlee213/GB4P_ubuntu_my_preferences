#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================================="
echo " Galaxy Book 4 Pro (GB4P) 전력 소모 최적화 설정 복원"
echo " (power_consumption)"
echo "========================================================="

# root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "[!] 관리자 권한이 필요합니다. sudo 로 재실행합니다..."
    exec sudo bash "$0" "$@"
fi

TARGET_USER="${SUDO_USER:-$USER}"
if [ "$TARGET_USER" = "root" ]; then
    TARGET_USER="$(who | awk '{print $1}' | head -n 1)"
    [ -z "$TARGET_USER" ] && TARGET_USER="hajun"
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

# 1. SSD 깨움 주기 지연 (sysctl) 복원
bash "${SCRIPT_DIR}/scripts/setup-power-sysctl.sh"
echo ""

# 2. 바탕화면 전원 옵션 도구 및 CPU 토폴로지 스크립트 복원
bash "${SCRIPT_DIR}/scripts/setup-power-options.sh"
echo ""

# 3. AC/DC 전원 감지 udev 룰 복원
bash "${SCRIPT_DIR}/scripts/setup-power-udev.sh"
echo ""

# 4. 부팅 시 자동 실행(autostart) 복원
bash "${SCRIPT_DIR}/scripts/setup-power-autostart.sh"
echo ""

# 5. 무암호 전원 스크립트 실행 sudoers 복원
bash "${SCRIPT_DIR}/scripts/setup-power-sudoers.sh"
echo ""

# 6. 현재 전원 상태(AC/DC) 즉시 반영
echo "-> 현재 전원 상태에 따른 프로필 즉시 적용..."
if [ -x "${TARGET_HOME}/Desktop/OneClickScripts/PowerOptions/handle_power_change.sh" ]; then
    bash "${TARGET_HOME}/Desktop/OneClickScripts/PowerOptions/handle_power_change.sh" || true
fi
echo ""

echo "========================================================="
echo " [SUCCESS] 전력 소모 최적화 설정 복원이 완료되었습니다!"
echo "========================================================="
echo " 1. SSD 깨움 주기 지연 (/etc/sysctl.d/99-ssd-power-saving.conf)"
echo "    - vm.dirty_writeback_centisecs = 6000 (60초 주기)"
echo "    - vm.dirty_expire_centisecs = 12000"
echo "    - vm.laptop_mode = 5"
echo " 2. CPU 하이브리드 토폴로지 최적화 (2P + 4E + 2LP-E, 총 8코어)"
echo "    - P코어 HT(보조스레드) 차단 (CPU 2, 4, 5, 7 OFF)"
echo "    - P코어 차단 (CPU 3, 6 OFF, 2P 체제 & Dark Silicon 완충구역)"
echo "    - 발열 밀집 E코어 Cluster 0 차단 (CPU 8~11 OFF)"
echo "    - 외곽 E코어 Cluster 1 활성화 (CPU 12~15 ON)"
echo "    - 저전력 LP-E코어 활성화 (CPU 16, 17 ON)"
echo " 3. AC/DC 자동 전환 시스템 (/etc/udev/rules.d/99-power-profile-switch.rules)"
echo "    - 🔌 AC (충전기 연결): 터보 ON (65% 제한) | Gnome/삼성 Balanced"
echo "    - 🔋 DC (배터리 모드): 터보 OFF (100% 클럭) | Gnome/삼성 Balanced (발열 방지)"
echo " 4. 부팅 시 자동 감지 & 적용 (~/.config/autostart/)"
echo " 5. 바탕화면 원클릭 도구 복원 (~/Desktop/OneClickScripts/PowerOptions/)"
echo "========================================================="
