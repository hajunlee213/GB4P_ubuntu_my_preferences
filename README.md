# Galaxy Book 4 Pro (GB4P) Ubuntu 개인 설정 원클릭 복원

갤럭시 북4 프로(GB4P, NT960XGK / Meteor Lake) 및 유사 기기에서 우분투를 재설치했을 때, **터치패드/키보드 편의 설정**과 **전력 소모 최적화(power_consumption)** 설정을 명령어 한 줄로 복원하기 위한 프로젝트입니다.

---

## 🚀 빠른 시작 (원클릭 복원)

우분투를 새로 설치한 후 터미널에서 원하는 복원 스크립트를 실행합니다:

```bash
git clone https://github.com/your-username/GB4P_ubuntu_my_preferences.git # (또는 로컬 복사본)
cd GB4P_ubuntu_my_preferences
chmod +x *.sh scripts/*.sh
```

### 1. 전력 소모 및 발열 최적화 복원 (`power_consumption.sh`)
```bash
./power_consumption.sh
```

### 2. 터치패드 팜리젝션 & 키보드(한영/한자) 복원 (`touchpad_keyboard.sh`)
```bash
./touchpad_keyboard.sh
```

---

## ⚡ power_consumption (전력 소모 & 발열 튜닝 상세)

인텔 메테오레이크(Meteor Lake Core Ultra 5 125H 등)의 높은 유휴/부하 전력 소모와 피크 발열(90°C+ 쓰로틀링)을 해결하기 위해 최적화된 설정들입니다.

### 1. CPU 하이브리드 아키텍처 토폴로지 최적화
* **P-core HT (하이퍼스레딩) 차단**:
  * CPU 2, 4, 5, 7번 비활성화 (순수 물리 P-core 0, 1, 3, 6번만 단독 사용)
  * 다중 스레드 경합으로 인한 불필요한 고전력 소모 및 급격한 발열 억제
* **E-core 다이 위치 기반 클러스터 분리 최적화**:
  * **Cluster 0 (CPU 8~11)**: P코어와 다이상 인접해 있어 열 집중을 유발하므로 **비활성화(OFF)**
  * **Cluster 1 (CPU 12~15)**: 다이 외곽에 위치하여 방열에 유리하므로 **활성화(ON)** 유지
* **LP-E Core (CPU 16, 17)**: 저전력 아일랜드 코어로 기본 활성화 유지
* **복원 경로**: `~/.local/bin/disable-ht.sh`, `~/.config/autostart/disable-ht.desktop`

### 2. SSD I/O 깨움 주기 지연 (VM Dirty Writeback 최적화)
* **목적**: 디스크(SSD)가 유휴 상태에서 불필요하게 15초마다 깨어나 전력을 낭비하는 현상 방지
* **설정 파일**: `/etc/sysctl.d/99-ssd-power-saving.conf`
  * `vm.dirty_writeback_centisecs = 6000`: 커널 flush 데몬 깨움 주기를 기본 15초에서 60초로 지연
  * `vm.dirty_expire_centisecs = 12000`: 더티 데이터 만료 시간 120초 지정
  * `vm.laptop_mode = 5`: 배터리 모드 시 I/O 쓰기 묶음 처리로 디스크 유휴 상태 극대화

### 3. AC(충전기) vs DC(배터리) 동적 자동 전환 시스템
* **커널 udev 룰**: `/etc/udev/rules.d/99-power-profile-switch.rules`
  * 충전기 어댑터(`ADP1`)의 연결/분리 이벤트를 실시간 감지하여 `handle_power_change.sh` 호출
  * `flock` 기반 중복 실행 방지(Lock) 및 0.3초 디바운스로 안정화 처리
* **🔌 AC 모드 (충전기 연결 시)**:
  * **터보 부스트**: ON (`no_turbo = 0`)
  * **클럭 상한선**: 65% (`max_perf_pct = 65`) - "2번 밸런스 터보"
  * **삼성 팬/Gnome 모드**: `Balanced` (성능과 발열 밸런스)
* **🔋 DC 모드 (배터리 사용 시)**:
  * **터보 부스트**: OFF (`no_turbo = 1`) - 20W+ 피크 전력 튐 및 급격한 방전 차단
  * **클럭 상한선**: 100% (`max_perf_pct = 100`) - 베이스 클럭 한도 내에서 100% 성능 쾌적하게 유지
  * **삼성 팬/Gnome 모드**: `Balanced` (적극적 쿨링을 유지하여 배터리 모드 발열 누적 원천 차단)

### 4. 부팅 시 자동 감지 & 적용 (Autostart)
* **설정 파일**: `~/.config/autostart/power-options-startup.desktop`
* **동작**: 부팅/로그인 직후 시스템 전원 상태(AC vs DC)를 자동 판별하여 최적 프로필 즉시 적용

### 5. 무암호 전원 제어 sudoers & 바탕화면 원클릭 도구
* **sudoers**: `/etc/sudoers.d/poweroptions` (원클릭 스크립트 실행 시 비밀번호 입력 생략)
* **바탕화면 원클릭 도구 모음 (`~/Desktop/OneClickScripts/PowerOptions/`)**:
  * `00_Full_Power.sh`: 임시 풀파워 세션 (모든 코어 ON / 터보 ON / 80% / 재부팅 시 롤백)
  * `1_unlimited_turbo_on.sh`: 터보 ON / 100% 풀파워
  * `1_unlimited_turbo_off.sh`: 터보 OFF / 100% 베이스 클럭 풀파워
  * `2_balanced_turbo_on.sh`: 터보 ON / 65% 밸런스 터보
  * `3_balanced_turbo_off.sh`: 터보 OFF / 80% 밸런스 절전
  * `4_powersave_turbo_off.sh`: 터보 OFF / 50% 최대 절전
  * `custom_limit.sh`: 대화형 클럭 제한/터보 설정 도구
  * `check_status.sh`: 활성 코어 수, 클럭, 팬모드, 온도 실시간 모니터링

---

## 🛠️ touchpad_keyboard (터치패드 & 키보드 튜닝 상세)

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
  - `/usr/local/bin/keyd` 심볼릭 링크 자동 생성

### 3. GNOME 터치패드 제스처 및 기본값
- `tap-to-click true`: 터치패드 탭하여 클릭
- `natural-scroll true`: 두 손가락 자연스러운 스크롤
- `disable-while-typing true`: 타이핑 중 터치패드 잠금
- `two-finger-scrolling-enabled true`: 두 손가락 스크롤 활성화

---

## 📂 프로젝트 구조

```
GB4P_ubuntu_my_preferences/
├── AGENT_README.md                # Agent 작업 가이드 및 규칙 지침서
├── touchpad_keyboard.sh           # 터치패드 & 키보드(keyd) 복원 스크립트
├── touchpad_keyboard.sh_README.md # 터치패드 & 키보드 패치 상세 설명서
├── power_consumption.sh           # 전력 소모 최적화 메인 복원 스크립트
├── power_consumption.sh_README.md  # 전력 소모 최적화 패치 상세 설명서
├── configs/
│   ├── sysctl/
│   │   └── 99-ssd-power-saving.conf  # SSD 깨움 지연 커널 파라미터
│   ├── udev/
│   │   └── 99-power-profile-switch.rules # AC/DC 자동 전환 감지 udev 룰
│   ├── sudoers/
│   │   └── poweroptions              # 무암호 전원 스크립트 실행 sudoers 템플릿
│   ├── autostart/
│   │   ├── power-options-startup.desktop # 부팅 시 전원 프로필 자동 적용
│   │   └── disable-ht.desktop            # 부팅 시 CPU 토폴로지 적용
│   ├── bin/
│   │   └── disable-ht.sh             # CPU HT 및 E코어 클러스터0 차단 스크립트
│   ├── power_options/                # 바탕화면 원클릭 전원 제어 도구 모음
│   │   ├── 00_Full_Power.sh
│   │   ├── 1_unlimited_turbo_off.sh
│   │   ├── 1_unlimited_turbo_on.sh
│   │   ├── 2_balanced_turbo_on.sh
│   │   ├── 3_balanced_turbo_off.sh
│   │   ├── 4_powersave_turbo_off.sh
│   │   ├── apply_on_boot.sh
│   │   ├── check_status.sh
│   │   ├── custom_limit.sh
│   │   ├── enable_all_ecores.sh
│   │   ├── handle_power_change.sh
│   │   └── README.md
│   ├── libinput/
│   │   └── local-overrides.quirks    # 터치패드 팜리젝션 & DWT quirks
│   └── keyd/
│       └── default.conf              # Alt_R/Ctrl_R -> 한영/한자 키 매핑
├── scripts/
│   ├── setup-power-sysctl.sh         # SSD 절전 sysctl 복원
│   ├── setup-power-options.sh        # 바탕화면 전원 도구 & CPU 제어 복원
│   ├── setup-power-udev.sh           # AC/DC 전환 udev 룰 복원
│   ├── setup-power-autostart.sh      # 부팅 자동 실행 항목 복원
│   ├── setup-power-sudoers.sh        # sudoers 무암호 권한 복원
│   ├── setup-touchpad.sh             # libinput 설정 복원
│   ├── setup-keyd.sh                 # keyd 설치 및 서비스 복원
│   └── setup-gnome.sh                # GNOME 터치패드 옵션 설정
└── README.md
```
