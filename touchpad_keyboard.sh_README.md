# touchpad_keyboard.sh 설명 문서

이 문서는 **[`touchpad_keyboard.sh`](./touchpad_keyboard.sh)** 스크립트가 적용하는 패치 내용, 동작 원리, 설정 파일 및 롤백 방법을 상세히 설명합니다.

---

## 1. 배경 및 해결하려는 문제

갤럭시 북4 프로(Galaxy Book 4 Pro, GB4P)에 우분투(24.04 / 26.04)를 설치했을 때 기본 상태에서 다음과 같은 하드웨어/입력 불편 사항이 발생합니다:

1. **터치패드 팜리젝션(Palm Rejection) 부족**:
   - 내장된 Zinitix 터치패드(`14E5:E760`)의 손바닥 감지 민감도가 기본 드라이버에서 비활성화되어 있거나 기준이 느슨하여, 타이핑 시 손바닥이 스치면 마우스 포인터가 제멋대로 튀는 현상이 발생합니다.
2. **keyd 가상 키보드로 인한 DWT(Disable-While-Typing) 무력화**:
   - 오른쪽 Alt/Ctrl을 한영/한자 키로 쓰기 위해 `keyd` 데몬을 띄우면, keyd가 `keyd virtual keyboard`라는 가상 장치를 생성합니다.
   - libinput은 이 가상 키보드를 '외장 키보드'로 간주하여 "내장 키보드 타이핑 시 터치패드 잠금" 기능이 풀려버리는 문제가 발생합니다.
3. **한영 / 한자 키 매핑 부재**:
   - 우분투 기본 상태에서는 물리적인 한영/한자 키가 없는 101/104키 배열 키보드에서 오른쪽 Alt와 Ctrl이 각각 `Alt_R`, `Control_R`로만 동작하므로 한영 전환에 불편이 있습니다.

---

## 2. 적용되는 설정 및 시스템 경로

이 스크립트는 다음 위치에 설정 파일 및 심볼릭 링크를 배치합니다:

| 대상 경로 | 설명 | 원본 파일 위치 |
| :--- | :--- | :--- |
| `/etc/libinput/local-overrides.quirks` | libinput 하드웨어 quirks (팜 감지 및 가상키보드 내장화) | [`configs/libinput/local-overrides.quirks`](./configs/libinput/local-overrides.quirks) |
| `/etc/keyd/default.conf` | keyd 키 리매핑 설정 (Right Alt ➡️ Hangul, Right Ctrl ➡️ Hanja) | [`configs/keyd/default.conf`](./configs/keyd/default.conf) |
| `/usr/local/bin/keyd` | Ubuntu 패키지 바이너리(`/usr/bin/keyd.rvaiya`) 심볼릭 링크 | 자동 생성 |
| GNOME gsettings | 터치패드 탭 클릭, 자연스러운 스크롤, 타이핑 시 잠금 | 스크립트 내 실행 |

---

## 3. 핵심 설정 파라미터 및 동작 원리

### (1) libinput Quirks (`/etc/libinput/local-overrides.quirks`)
```ini
# 1. keyd 가상 키보드를 내장 키보드로 인식 -> 타이핑 중 터치패드 잠금(DWT) 정상화
[keyd Virtual Keyboard Integration]
MatchName=keyd virtual keyboard
AttrKeyboardIntegration=internal

# 2. 갤럭시북 Zinitix 터치패드 손바닥 크기/압력 감지
[Samsung Galaxy Book ZNT Touchpad]
MatchUdevType=touchpad
MatchBus=i2c
MatchVendor=0x14E5
MatchProduct=0xE760
AttrPalmPressureThreshold=100
AttrPalmSizeThreshold=20
```
- `AttrKeyboardIntegration=internal`: keyd 가상 키보드에서 키 입력이 발생해도 내장 키보드에서 타이핑한 것과 동일하게 취급되어, libinput이 터치패드를 즉시 일시 중단(DWT)시킵니다.
- `AttrPalmPressureThreshold=100`, `AttrPalmSizeThreshold=20`: 손가락 끝보다 넓은 면적(접촉 크기 20 이상) 또는 일정 압력 이상의 접촉을 손바닥으로 인식하여 포인터 이동 이벤트에서 무시합니다.

### (2) keyd 설정 (`/etc/keyd/default.conf`)
```ini
[ids]
*

[main]
rightalt = hangeul
rightcontrol = hanja
```
- 모든 키보드 장치(`*`)에 대해:
  - 오른쪽 Alt 키 이벤트를 Linux 커널 표준 `KEY_HANGEUL` 키코드로 변환합니다.
  - 오른쪽 Ctrl 키 이벤트를 Linux 커널 표준 `KEY_HANJA` 키코드로 변환합니다.

### (3) Ubuntu 26.04 패키지 호환 처리
- Ubuntu/Debian 공식 패키지는 기존 `onak` 패키지와의 이름 충돌을 피하기 위해 실행 파일명이 `/usr/bin/keyd.rvaiya`로 패키징되어 있습니다.
- 스크립트가 `/usr/local/bin/keyd -> /usr/bin/keyd.rvaiya` 심볼릭 링크를 생성하므로 사용자는 터미널에서 표준 `keyd` CLI 명령을 그대로 사용할 수 있습니다.

---

## 4. 수동 확인 및 테스트 명령어

- **keyd 동작 상태 확인**:
  ```bash
  systemctl status keyd
  ```
- **키 입력 실시간 모니터링** (Right Alt/Ctrl 누를 때 `hangeul`, `hanja`로 찍히는지 확인):
  ```bash
  sudo keyd monitor
  ```
- **설정 즉시 리로드**:
  ```bash
  sudo keyd reload
  ```

---

## 5. 롤백 (설정 원상 복구) 방법

해당 설정을 완전히 제거하고 우분투 순정 상태로 되돌리려면 다음 명령어를 실행합니다:

```bash
# 1. libinput quirks 제거
sudo rm -f /etc/libinput/local-overrides.quirks

# 2. keyd 서비스 중지 및 설정 제거
sudo systemctl stop keyd
sudo systemctl disable keyd
sudo rm -f /etc/keyd/default.conf
sudo rm -f /usr/local/bin/keyd

# 3. 변경사항 적용을 위해 재부팅 또는 로그아웃
```
