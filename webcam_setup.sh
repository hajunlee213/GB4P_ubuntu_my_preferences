#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================================="
echo " Galaxy Book 4 Pro (GB4P) 웹캠 드라이버 & Relay 원클릭 복원"
echo " (webcam_setup: 180도 회전, 크롬 인식, 복불복 방지, On-Demand Relay)"
echo "========================================================="

# root 권한 확인 및 자동 승격
if [ "$EUID" -ne 0 ]; then
    echo "[!] 관리자 권한이 필요합니다. sudo 로 재실행합니다..."
    exec sudo bash "$0" "$@"
fi

# 롤백 옵션 (--restore 또는 --uninstall) 처리
if [ "${1:-}" = "--restore" ] || [ "${1:-}" = "--uninstall" ]; then
    bash "${SCRIPT_DIR}/scripts/restore-webcam.sh"
    exit 0
fi

# 1. 웹캠 드라이버 및 Relay 복원 실행
bash "${SCRIPT_DIR}/scripts/setup-webcam.sh"
echo ""

echo "========================================================="
echo " [SUCCESS] 웹캠 드라이버 및 On-Demand Relay 복원이 완료되었습니다!"
echo "========================================================="
echo " 1. 180도 센서 뒤집힘 하드웨어 보정:"
echo "    - ipu-bridge-fix (v1.4) DKMS 설치 (DMI 960XGK 매칭)"
echo "    - 커널 레벨 180도 회전 인식으로 브라우저, 디스코드 등 시스템 전역 정상 출력"
echo " 2. 크롬/엣지(Chromium) 웹캠 인식 완벽 지원:"
echo "    - /etc/modprobe.d/99-camera-relay-loopback.conf: exclusive_caps=1"
echo "    - /etc/modules-load.d/v4l2loopback.conf: 부팅 선행 로드로 /dev/video0 선점"
echo "    - /etc/udev/rules.d/70-camera-relay-capabilities.rules: ID_V4L_CAPABILITIES=:capture:"
echo "    - /etc/udev/rules.d/90-hide-ipu6-v4l2.rules: 원시 IPU6 노드 은닉"
echo " 3. 부팅 시 복불복 꺼짐(레이스 컨디션) 원천 해결:"
echo "    - /etc/dracut.conf.d/ipu6-firmware.conf: ipu6epmtl_fw.bin initramfs 사전 탑재"
echo "    - 루트 파일시스템 마운트 전 펌웨어 로드 실패 방지"
echo " 4. 26MHz 외부 클록 호환:"
echo "    - ov02c10-26mhz-fix DKMS 설치 (Meteor Lake 26MHz 클록 에러 차단)"
echo " 5. On-Demand 전력/발열 초절전 백그라운드 릴레이:"
echo "    - ~/.config/systemd/user/camera-relay.service 활성화"
echo "    - 앱이 웹캠을 열 때만 파이프라인 가동 (미사용 시 CPU/배터리 0%)"
echo "========================================================="
echo ""
echo " 🚀 필수 안내:"
echo " 1. initramfs 펌웨어 번들 및 커널 모듈 설정을 시스템에 완전히 적용하려면"
echo "    시스템 재부팅을 권장합니다:"
echo "    sudo reboot"
echo ""
echo " 2. 재부팅 후 웹캠 상태 확인 명령어:"
echo "    - Relay 상태 확인: camera-relay status"
echo "    - 진단 리포트 출력: camera-relay doctor"
echo "    - 디바이스 확인: v4l2-ctl --list-devices"
echo "    - DKMS 모듈 확인: dkms status"
echo ""
echo " 3. 언제든지 설정을 순정으로 되돌리려면 아래 명령을 실행하세요:"
echo "    sudo ./webcam_setup.sh --restore"
echo "========================================================="
