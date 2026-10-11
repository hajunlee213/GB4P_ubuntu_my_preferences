#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================================="
echo " Galaxy Book 4 Pro (GB4P) 지문인식 드라이버 & PAM 원클릭 복원"
echo " (Egis 1c7a:05a1 SDCP v2 + PAM 3회/30초 최적화)"
echo "========================================================="

# root 권한 확인 및 자동 승격
if [ "$EUID" -ne 0 ]; then
    echo "[!] 관리자 권한이 필요합니다. sudo 로 재실행합니다..."
    exec sudo bash "$0" "$@"
fi

# 롤백 옵션 처리
if [ "${1:-}" = "--restore" ] || [ "${1:-}" = "--uninstall" ]; then
    bash "${SCRIPT_DIR}/scripts/restore-libfprint.sh"
    # PAM 순정 복구 (1회/10초)
    sed -i 's/pam_fprintd\.so.*/pam_fprintd.so max-tries=1 timeout=10 # debug/' /usr/share/pam-configs/fprintd || true
    pam-auth-update --package || true
    echo "[SUCCESS] 지문인식 드라이버 및 PAM 설정이 순정 상태로 롤백되었습니다."
    exit 0
fi

# 1. libfprint SDCP Version 2 패치 드라이버 복원
bash "${SCRIPT_DIR}/scripts/setup-libfprint.sh"
echo ""

# 2. PAM 지문인식 옵션(3회 시도, 30초 대기) 복원
bash "${SCRIPT_DIR}/scripts/setup-pam-fprint.sh"
echo ""

echo "========================================================="
echo " [SUCCESS] 지문인식 센서 및 PAM 설정 복원이 완료되었습니다!"
echo "========================================================="
echo " 1. Egis SDCP 패치 드라이버(v2):"
echo "    - 호스트 키 영구 보존: 재부팅 후에도 등록된 지문 100% 보존"
echo "    - fprintd Crash 방지: task_ssm 메모리 누수 해결로 데몬 비정상 종료 차단"
echo "    - 강제 SDCP 재연결: 절전/화면 잠금 복귀 시 센서 기억상실(65 E0) 완벽 해결"
echo "    - 세션 만료 무제한: 24시간 후 세션 파기 방지"
echo " 2. PAM 인증 최적화:"
echo "    - 최대 시도 횟수: 3회 (우분투 기본 1회 -> 3회 확장)"
echo "    - 타임아웃: 30초 (우분투 기본 10초 -> 30초 확장)"
echo "========================================================="
echo " 🚀 사용 방법:"
echo " - 신규 지문 등록: fprintd-enroll"
echo " - 등록된 지문 확인: fprintd-list \$USER"
echo " - 지문 인증 테스트: fprintd-verify"
echo " - 순정 롤백: sudo ./fingerprint_setup.sh --restore"
echo "========================================================="
