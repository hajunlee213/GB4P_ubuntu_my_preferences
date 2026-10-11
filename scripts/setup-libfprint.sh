#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== [1/2] Egis SDCP 지문인식 패치 드라이버(v2) 복원 시작 ==="

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] 이 스크립트는 root 권한(sudo)으로 실행해야 합니다." >&2
    exit 1
fi

LIB_SRC="${PROJECT_ROOT}/configs/libfprint/libfprint-2.so.2.0.0"
LIB_DIR="/usr/local/lib/x86_64-linux-gnu"
LIB_DEST="${LIB_DIR}/libfprint-2.so.2.0.0"

# 1. 필수 패키지 확인 및 설치
if ! dpkg -s libpam-fprintd fprintd &>/dev/null; then
    echo "-> 필수 패키지(fprintd, libpam-fprintd) 설치..."
    apt-get update -qq
    apt-get install -y -qq fprintd libpam-fprintd
fi

# 2. 사전 빌드된 Version 2 패치 바이너리 배포
if [ ! -f "${LIB_SRC}" ]; then
    echo "[ERROR] 패치 라이브러리 바이너리를 찾을 수 없습니다: ${LIB_SRC}" >&2
    exit 1
fi

echo "-> 패치된 libfprint 라이브러리 설치 (${LIB_DEST})..."
mkdir -p "${LIB_DIR}"
cp "${LIB_SRC}" "${LIB_DEST}"
chmod 755 "${LIB_DEST}"

# 심볼릭 링크 생성
ln -sf libfprint-2.so.2.0.0 "${LIB_DIR}/libfprint-2.so.2"
ln -sf libfprint-2.so.2 "${LIB_DIR}/libfprint-2.so"

echo "-> ldconfig 갱신..."
ldconfig

# 3. 기존 SDCP 세션 캐시 초기화
echo "-> 이전 SDCP 세션 claim 캐시 정리..."
rm -f /var/lib/fprint/sdcp-claim-*

# 4. fprintd 서비스 재시작
echo "-> fprintd 서비스 재시작..."
systemctl restart fprintd.service || true

echo "[SUCCESS] Egis SDCP 패치 드라이버(v2) 설치 및 적용 완료!"
