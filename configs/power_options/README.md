# 💻 삼성 갤럭시북4 프로(NT960XGK) 전원 & 팬 제어 시스템 매뉴얼

이 문서는 우분투(Ubuntu 26.04) 환경에서 **삼성 갤럭시북4 프로(NT960XGK, Meteor Lake)**의 전원 관리, CPU 클럭 상한선 제어, AC/DC 자동 전환 시스템의 설정 내역 및 유지보수 가이드입니다.

---

## 1. 시스템 환경 및 하드웨어 정보

* **기기 모델**: 삼성 갤럭시북4 프로 16인치 (`NT960XGK` / Intel Core Ultra Meteor Lake)
* **운영체제**: Ubuntu 26.04 LTS (Kernel 7.0.x / 6.15+ Mainline)
* **플랫폼 드라이버**: 리눅스 커널 내장 `samsung_galaxybook` (`SAM0430:00`)
* **CPU 전원 드라이버**: `intel_pstate` (Hardware P-States / HWP)

---

## 2. 핵심 동작 원리

1. **하드웨어 팬 제어 (`platform_profile`)**:
   * 삼성 임베디드 컨트롤러(EC)는 ACPI `platform_profile` 인터페이스를 통해 4단계 팬 모드를 지원합니다.
   * `low-power` (무소음/0 RPM) | `quiet` (저소음) | `balanced` (최적화) | `performance` (최대 회전)
2. **CPU 클럭 및 전력 상한 제어 (`intel_pstate`)**:
   * `/sys/devices/system/cpu/intel_pstate/no_turbo` (0: 터보 ON / 1: 터보 OFF)
   * `/sys/devices/system/cpu/intel_pstate/max_perf_pct` (10~100% 글로벌 클럭 상한)
   * 인텔 하이브리드 아키텍처(P코어/E코어/LPE코어) 전체에 일괄 적용되어 90°C 이상의 과열 및 서멀 쓰로틀링을 원천 방지합니다.
3. **비밀번호 자동 인증**:
   * 모든 스크립트는 `sudo -S true` 선인증 방식을 사용하여 실행 시 비밀번호 입력창 없이 즉시 0.01초 만에 실행됩니다. (기본 sudo 비밀번호: `0000`)

---

## 3. 디렉토리 구조 및 파일 목록

📁 **작업 경로**: `/home/hajun/Desktop/OneClickScripts/PowerOptions/`

| 파일명 | 유형 | 터보 부스트 | 클럭 상한 | 설명 |
| :--- | :---: | :---: | :---: | :--- |
| **`00_Full_Power.sh`** *(신규)* | 원클릭 | **ON** | **80%** | **세션 임시 풀파워**: 모든 코어 온라인 + 터보 ON + Performance (재부팅 시 롤백) |
| **`1_unlimited_turbo_on.sh`** | 원클릭 | **ON** | **100%** | **무제한 성능** (컴파일/고사양 작업 시 풀 부스트 파워) |
| **`1_unlimited_turbo_off.sh`** | 원클릭 | **OFF** | **100%** | **풀파워 터보 OFF**: 베이스 클럭 100% 최대 활용 + 터보 발열 차단 |
| **`2_balanced_turbo_on.sh`** | 원클릭 | **ON** | **65%** | **기본 권장 (밸런스 터보)**: 터보 반응성 유지 + 80°C 이하 발열 제어 |
| **`3_balanced_turbo_off.sh`** | 원클릭 | **OFF** | **80%** | **밸런스 절전**: 터보 발열 차단 + 쾌적한 기본 클럭 유지 |
| **`4_powersave_turbo_off.sh`** | 원클릭 | **OFF** | **50%** | **최대 절약**: 배터리 극대화 / 저발열 / 완전 절전 |
| **`custom_limit.sh`** | 대화형 | 선택 | 직접 입력 | 사용자가 원하는 수치(10~100%)와 터보 ON/OFF를 대화형으로 입력 |
| **`check_status.sh`** | 모니터링 | - | - | 현재 터보 상태, 클럭 제한(%), 코어별 실시간 클럭, 온도 점검 |
| **`apply_on_boot.sh`** | 시스템 | - | - | 부팅(로그인) 시 AC/DC 상태를 판별하여 자동 실행 |
| **`handle_power_change.sh`** | 시스템 | - | - | 충전기 연결(AC) / 분리(DC) 시 커널 udev가 자동 호출하는 핸들러 |

---

## 4. 시스템 자동화 및 영구 설정 내역

### 1) AC / DC 자동 전환 규칙 (`udev`)
* **설정 파일**: `/etc/udev/rules.d/99-power-profile-switch.rules`
* **동작 규칙**:
  * **🔌 AC (충전기 연결 시)**: Gnome `Balanced` + 터보 ON / 65% (P: ~2.9GHz / E: ~2.3GHz)
  * **🔋 DC (배터리 사용 시)**: Gnome `Balanced` + 터보 ON / 40% (P: ~2.0GHz / E: ~1.5GHz Race to Sleep 최적화)
* **영구 유지**: 재부팅 후에도 영구적으로 자동 동작합니다.

### 2) 부팅 시 자동 실행 (`autostart`)
* **설정 파일**: `~/.config/autostart/power-options-startup.desktop`
* **동작**: 사용자 로그인 시 `apply_on_boot.sh`를 실행하여 현재 전원 상태에 알맞은 모드를 즉시 설정합니다.

### 3) 초고속 실행을 위한 sudoers 면제 설정 (기등록 권장)
* **설정 파일**: `/etc/sudoers.d/poweroptions`
* **내용**:
  ```sudoers
  hajun ALL=(ALL) NOPASSWD: /home/hajun/Desktop/OneClickScripts/PowerOptions/*.sh
  ```

---

## 5. 유지보수 및 튜닝 가이드 (새 세션 참고용)

### Q1. 부팅 기본 모드 또는 AC/DC 동작 모드를 변경하고 싶을 때
* `~/Desktop/OneClickScripts/PowerOptions/handle_power_change.sh` 파일을 열어서 원하는 스크립트 경로(`2_balanced_turbo_on.sh` 등)로 교체합니다.

### Q2. 2번 밸런스 터보의 클럭 상한(65%)을 다른 수치로 바꾸고 싶을 때
* `~/Desktop/OneClickScripts/PowerOptions/2_balanced_turbo_on.sh` 파일 내의 `echo 65 > ...` 라인의 숫자를 수정합니다.

### Q3. 실시간 하드웨어 상태 확인 명령어
```bash
~/Desktop/OneClickScripts/PowerOptions/check_status.sh
```
또는 터미널 직접 조회:
```bash
# 1. P-State 설정 확인
cat /sys/devices/system/cpu/intel_pstate/no_turbo        # 0: 터보ON, 1: 터보OFF
cat /sys/devices/system/cpu/intel_pstate/max_perf_pct     # 현재 클럭 상한(%)
cat /sys/firmware/acpi/platform_profile                  # 현재 삼성 팬 모드

# 2. 실시간 CPU 온도
paste <(cat /sys/class/thermal/thermal_zone*/type) <(cat /sys/class/thermal/thermal_zone*/temp) | awk '{printf "%-20s : %.1f°C\n", $1, $2/1000}' | grep -E 'x86|TCPU'
```
