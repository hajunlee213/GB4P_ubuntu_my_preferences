#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================================="
echo " Galaxy Book 4 Pro (GB4P) Ubuntu 개인 설정 원클릭 복원"
echo "========================================================="

# root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "[!] 관리자 권한이 필요합니다. sudo 로 재실행합니다..."
    exec sudo bash "$0" "$@"
fi

# 1. 터치패드 팜리젝션 및 quirks 복원
bash "${SCRIPT_DIR}/scripts/setup-touchpad.sh"
echo ""

# 2. keyd 한영/한자 키 리매핑 복원
bash "${SCRIPT_DIR}/scripts/setup-keyd.sh"
echo ""

# 3. GNOME 터치패드 설정 복원
bash "${SCRIPT_DIR}/scripts/setup-gnome.sh"
echo ""

echo "========================================================="
echo " [SUCCESS] 모든 개인 설정 복원이 완료되었습니다!"
echo "========================================================="
echo " 1. 터치패드 팜리젝션: /etc/libinput/local-overrides.quirks 적용됨"
echo " 2. keyd 한영/한자 키 매핑: /etc/keyd/default.conf 적용됨"
echo "    - Alt_R  -> Hangul (KEY_HANGEUL)"
echo "    - Ctrl_R -> Hanja  (KEY_HANJA)"
echo "    - CLI 명령어 'keyd' 사용 가능 (/usr/local/bin/keyd)"
echo " 3. GNOME 터치패드 옵션: 탭 클릭, 자연스러운 스크롤, 타이핑 중 잠금 적용됨"
echo "========================================================="
