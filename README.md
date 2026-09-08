# Galaxy Book 4 Pro (GB4P) Ubuntu 개인 설정 원클릭 복원

갤럭시 북4 프로(GB4P) 및 유사 기기에서 우분투를 재설치했을 때, **터치패드 팜리젝션(Palm Rejection)** 개선과 **keyd 한영/한자 키 리매핑** 설정을 명령어 한 줄로 복원하기 위한 프로젝트입니다.

---

## 🚀 빠른 시작 (원클릭 복원)

우분투를 새로 설치한 후 터미널에서 다음 명령어를 실행합니다:

```bash
git clone https://github.com/your-username/GB4P_ubuntu_my_preferences.git # (또는 로컬 복사본)
cd GB4P_ubuntu_my_preferences
chmod +x touchpad_keyboard.sh scripts/*.sh
./touchpad_keyboard.sh
```

---

## 🛠 적용되는 설정 상세

### 1. 터치패드 팜리젝션 & DWT 연동 (`/etc/libinput/local-overrides.quirks`)
- **Zinitix 터치패드 (`14E5:E760`) 튜닝**:
  - `AttrPalmPressureThreshold=100`: 가벼운 손바닥 닿음 압력 감지
  - `AttrPalmSizeThreshold=20`: 접촉 면적이 넓은 손바닥 터치를 포인터 이동에서 제외
- **keyd 가상 키보드 DWT(Disable-While-Typing) 활성화**:
  - `AttrKeyboardIntegration=internal`: keyd 가상 키보드를 '내장 키보드'로 인식시켜 키보드 타이핑 도중 터치패드가 튀는 현상 차단

### 2. keyd 한영/한자 키 리매핑 (`/etc/keyd/default.conf`)
- **리매핑 규칙**:
  - **오른쪽 Alt (Alt_R)** ➡️ **한영 키 (Hangul / KEY_HANGEUL)**
  - **오른쪽 Ctrl (Ctrl_R)** ➡️ **한자 키 (Hanja / KEY_HANJA)**
- **Ubuntu 26.04 패키지 호환**:
  - Ubuntu/Debian 공식 패키지는 바이너리가 `/usr/bin/keyd.rvaiya`로 설치되므로, 스크립트가 자동으로 `/usr/local/bin/keyd` 심볼릭 링크를 생성하여 어디서나 `keyd` 명령어로 사용할 수 있게 합니다.

### 3. GNOME 터치패드 제스처 및 기본값
- `tap-to-click true`: 터치패드 탭하여 클릭
- `natural-scroll true`: 두 손가락 자연스러운 스크롤
- `disable-while-typing true`: 타이핑 중 터치패드 잠금
- `two-finger-scrolling-enabled true`: 두 손가락 스크롤 활성화

---

## ⌨️ keyd 유용한 명령어 모음

### 'Alt_R -> Hangul, Ctrl_R -> Hanja' 설정 관련 명령어

- **설정 파일로 영구 적용 (`/etc/keyd/default.conf`)**:
  ```ini
  [ids]
  *

  [main]
  rightalt = hangeul
  rightcontrol = hanja
  ```

- **설정 즉시 리로드**:
  ```bash
  sudo keyd reload
  ```

- **터미널에서 즉시 런타임 바인딩 (파일 수정 없이 메모리에 즉시 반영)**:
  ```bash
  sudo keyd bind "main.rightalt = hangeul" "main.rightcontrol = hanja"
  ```

- **키 입력 및 매핑 실시간 모니터링**:
  ```bash
  sudo keyd monitor
  ```
  *(터미널을 켜두고 오른쪽 Alt/Ctrl 키를 눌러 `hangeul`, `hanja`로 이벤트가 발생하는지 확인 가능)*

- **지원하는 키 명칭 목록 확인**:
  ```bash
  keyd list-keys | grep -E "hangeul|hanja|rightalt|rightcontrol"
  ```

---

## 📂 프로젝트 구조

```
GB4P_ubuntu_my_preferences/
├── touchpad_keyboard.sh           # 터치패드 & 키보드(keyd) 복원 스크립트
├── configs/
│   ├── libinput/
│   │   └── local-overrides.quirks    # 터치패드 팜리젝션 & DWT quirks
│   └── keyd/
│       └── default.conf              # Alt_R/Ctrl_R -> 한영/한자 키 매핑
├── scripts/
│   ├── setup-touchpad.sh          # libinput 설정 복원
│   ├── setup-keyd.sh              # keyd 설치, 링크 및 서비스 활성화
│   └── setup-gnome.sh             # GNOME 데스크톱 터치패드 옵션 설정
└── README.md
```
