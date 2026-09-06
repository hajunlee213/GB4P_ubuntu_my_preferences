#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== [2/3] keyd 한영/한자 키 리매핑 설정 복원 시작 ==="

# root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] 이 스크립트는 root 권한(sudo)으로 실행해야 합니다." >&2
    exit 1
fi

KEYD_CONF_SRC="${PROJECT_ROOT}/configs/keyd/default.conf"
KEYD_CONF_DEST="/etc/keyd/default.conf"

# 1. keyd 패키지 설치 확인
if ! command -v keyd >/dev/null 2>&1 && ! command -v keyd.rvaiya >/dev/null 2>&1; then
    echo "-> keyd 패키지가 설치되어 있지 않아 apt로 설치를 진행합니다..."
    apt-get update
    apt-get install -y keyd
fi

# 2. Ubuntu 패키지 호환 심볼릭 링크 생성 (/usr/local/bin/keyd)
# Ubuntu/Debian에서는 onak 패키지와의 이름 충돌로 바이너리가 /usr/bin/keyd.rvaiya 로 제공됨
if [ -x /usr/bin/keyd.rvaiya ] && [ ! -e /usr/local/bin/keyd ]; then
    echo "-> /usr/local/bin/keyd 심볼릭 링크 생성 (/usr/bin/keyd.rvaiya -> keyd)..."
    ln -sf /usr/bin/keyd.rvaiya /usr/local/bin/keyd
fi

KEYD_BIN="$(command -v keyd || command -v keyd.rvaiya)"

# 3. 설정 파일 복사
if [ ! -f "${KEYD_CONF_SRC}" ]; then
    echo "[ERROR] keyd 설정 파일을 찾을 수 없습니다: ${KEYD_CONF_SRC}" >&2
    exit 1
fi

echo "-> /etc/keyd 디렉토리 생성 및 설정 파일 복사..."
mkdir -p /etc/keyd
cp "${KEYD_CONF_SRC}" "${KEYD_CONF_DEST}"
chmod 644 "${KEYD_CONF_DEST}"

echo "-> 적용된 keyd 설정:"
cat "${KEYD_CONF_DEST}"

# 4. systemd 서비스 활성화 및 시작
echo "-> keyd systemd 서비스 활성화 및 시작..."
systemctl daemon-reload
systemctl enable --now keyd

# 5. 설정 리로드
echo "-> keyd reload 실행..."
"${KEYD_BIN}" reload || systemctl restart keyd

echo "[SUCCESS] keyd 설정 완료!"
echo "Right Alt -> Hangul (KEY_HANGEUL)"
echo "Right Ctrl -> Hanja (KEY_HANJA)"
