#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================================="
echo " Galaxy Book 4 Pro (GB4P) PAM 지문인식(fprintd) 옵션 최적화"
echo " (max-tries=3, timeout=30)"
echo "========================================================="

# root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "[!] 관리자 권한이 필요합니다. sudo 로 재실행합니다..."
    exec sudo bash "$0" "$@"
fi

# 1. PAM fprintd 프로필 및 common-auth 갱신
bash "${SCRIPT_DIR}/scripts/setup-pam-fprint.sh"

echo ""
echo "========================================================="
echo " [SUCCESS] PAM 지문인식 옵션 최적화가 완료되었습니다!"
echo "========================================================="
echo " 1. /usr/share/pam-configs/fprintd: max-tries=3 timeout=30"
echo " 2. /etc/pam.d/common-auth: pam-auth-update 갱신 완료"
echo "========================================================="
