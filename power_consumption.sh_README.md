# power_consumption.sh 설명 문서

이 문서는 **[`power_consumption.sh`](./power_consumption.sh)** 스크립트가 적용하는 패치 내용, 동작 원리, 설정 파일 및 롤백 방법을 상세히 설명합니다.

---

## 1. 배경 및 해결하려는 문제

삼성 갤럭시 북4 프로(GB4P, Intel Core Ultra / Meteor Lake 아키텍처)는 고해상도 OLED 디스플레이와 다핵 하이브리드 CPU를 탑재하고 있어 리눅스 우분투 기본 환경에서 다음과 같은 전력 및 발열 문제가 발생합니다:

1. **NVMe SSD의 잦은 웨이크업(Wakeup)으로 인한 배터리 소모**:
   - 리눅스 기본 커널 설정에서는 디스크 캐시 dirty writeback 주기가 5초 단위로 짧게 돌아가 SSD가 절전 상태(APST / NVMe low power state)에 머무르지 못하고 자주 깨어납니다.
2. **Meteor Lake 하이브리드 CPU(P + E + LP-E)의 고발열 구조**:
   - P코어의 하이퍼스레딩(HT)과 물리적으로 밀집된 E코어 클러스터(Cluster 0)가 동시에 풀가동될 때 쿨링팬 소음 및 발열 스로틀링이 극심해집니다.
3. **충전기(AC) 및 배터리(DC) 전환 시 수동 설정의 번거로움**:
   - 배터리 사용 시에는 인텔 터보 부스트를 꺼서 배터리 수명을 대폭 확보하고, 충전기 연결 시에는 적절한 클럭 제한과 함께 성능을 내도록 자동 감지/전환 시스템이 필요합니다.

---

## 2. 적용되는 설정 및 시스템 경로

이 스크립트는 다음 위치에 설정 파일 및 도구들을 배치합니다:

| 대상 경로 | 설명 | 원본 파일 위치 |
| :--- | :--- | :--- |
| `/etc/sysctl.d/99-ssd-power-saving.conf` | SSD 더티 페이지 쓰기 주기 지연 및 laptop_mode 설정 | [`configs/sysctl/99-ssd-power-saving.conf`](./configs/sysctl/99-ssd-power-saving.conf) |
| `/etc/udev/rules.d/99-power-profile-switch.rules` | AC/DC 전원 어댑터 연결/분리 이벤트 감지 udev 룰 | [`configs/udev/99-power-profile-switch.rules`](./configs/udev/99-power-profile-switch.rules) |
| `/etc/sudoers.d/poweroptions` | 전원 스크립트 실행 시 비밀번호 입력을 면제하는 sudoers 설정 | [`configs/sudoers/poweroptions`](./configs/sudoers/poweroptions) |
| `/etc/modprobe.d/iwlwifi.conf` | Intel Wi-Fi 모듈 초절전 모드 (power_save=1, power_level=5) | [`configs/modprobe/iwlwifi.conf`](./configs/modprobe/iwlwifi.conf) |
| `~/.local/bin/disable-ht.sh` | CPU 하이퍼스레딩 및 하이브리드 코어 토폴로지 제어 스크립트 | [`configs/bin/disable-ht.sh`](./configs/bin/disable-ht.sh) |
| `~/.config/autostart/` | 부팅 시 전원 프로필 및 CPU 토폴로지 자동 적용 데스크톱 항목 | [`configs/autostart/`](./configs/autostart/) |
| `~/Desktop/OneClickScripts/PowerOptions/` | 바탕화면에서 원클릭으로 전원/터보 모드를 변경하는 도구 모음 | [`configs/power_options/`](./configs/power_options/) |

---

## 3. 핵심 설정 파라미터 및 동작 원리

### (1) SSD 전력 소모 지연 (`/etc/sysctl.d/99-ssd-power-saving.conf`)
```ini
vm.dirty_writeback_centisecs = 6000
vm.dirty_expire_centisecs = 12000
vm.laptop_mode = 5
```
- writeback 주기를 기존 5초에서 60초(6000 centisecs)로 대폭 늘려 SSD의 불필요한 깨어남을 억제하고 NVMe 깊은 절전 모드를 유지합니다.

### (2) CPU 하이브리드 토폴로지 최적화 (`~/.local/bin/disable-ht.sh`)
- **P-코어 완전 차단 (CPU 1~7 OFF)**:
  - P-코어 물리 코어 및 하이퍼스레딩(CPU 1, 2, 3, 4, 5, 6, 7)을 하드웨어적으로 오프라인
- **CPU 0 식물인간 격리 (C10 Deep Sleep 극대화)**:
  - x86 아키텍처의 Bootstrap Processor(BSP) 특성상 CPU 0은 커널 하드웨어 차원(`cpu0/online`)에서 오프라인을 지원하지 않음
  - systemd cgroups v2의 `systemctl set-property user.slice AllowedCPUs=8-15` 및 `user-1000.slice AllowedCPUs=8-15`를 통해 사용자 세션의 모든 프로세스(GNOME 셸, 렌더러, 브라우저 스레드 등)의 실행 가능 CPU를 E-코어(8-15)로 완전 한정
  - CPU 0은 최소한의 커널 타이머/인터럽트만 처리하며 99.5% 이상 하드웨어 C10 딥슬립 상태에 머무름
- **E-코어 8개 전담 가동 (Cluster 0 & 1, CPU 8~15 ON)**:
  - 브라우저 및 일반 작업 전체를 E-코어 8개가 전담 처리
  - 면적이 넓고 전력 밀도가 낮은 Crestmont 클러스터에 부하가 분산되어 피크 핫스팟이 제거되고 극저발열/무소음 달성
- **LP-E 코어 (CPU 16, 17) 차단**:
  - 실효성 없이 TLB shootdown과 인터럽트로 깨어나는 SoC 타일 코어를 꺼서 SoC-Compute 타일 간 패브릭 인터커넥트 병목 및 슬립 낭비 원천 제거

### (3) AC/DC 자동 전환 시스템 (`/etc/udev/rules.d/99-power-profile-switch.rules`)
- **🔌 충전기(AC) 연결 시**: 터보 부스트 ON (80% 클럭 제한) + 균형 모드 + EPP `balance_performance`
  - E-코어 8개 ~3.0GHz 구동 (총 24.0 GHz·core 연산력으로 고부하/컴파일 시 쾌적한 반응성 제공)
- **🔋 배터리(DC) 전환 시**: 터보 부스트 ON (70% 클럭 제한) + 균형 모드 + EPP `power`
  - E-코어 8개 ~2.5GHz 구동 (총 20.0 GHz·core 연산력 제공, 전성비 최적 구간 ~2.5GHz를 활용하여 멀티태스킹 반응성과 저발열 최적 균형 달성)

### (4) 전력 최적화 고급 튜닝
- **커서 깜빡임 차단 (`cursor-blink = false`)**:
  - 터미널 및 텍스트 편집기에서 1초마다 깜빡이는 커서로 인한 디스플레이 버퍼 갱신을 차단
  - eDP 패널이 `PSR2 SLEEP` (패널 자체 메모리로 화면 유지, GPU 및 디스플레이 링크 완전 수면) 상태를 유지하도록 하여 GPU RC6 진입률을 극대화
- **PackageKit 서비스 unmask 보장 (App Center 호환성)**:
  - 우분투 App Center 'Manage(관리)' 탭의 deb 패키지 목록 및 업데이트 조회가 정상 동작하도록 PackageKit 서비스 unmask 상태 유지
- **Intel Workload Type Hints 활성화 (`workload_hint_enable = 1`)**:
  - 메테오레이크 CPU에 내장된 하드웨어 워크로드 감지 전력 최적화 기능 활성화
- **Intel Wi-Fi 초절전 파라미터 (`/etc/modprobe.d/iwlwifi.conf`)**:
  - `options iwlwifi power_save=1 power_level=5`를 등록하여 무선 칩셋의 유휴 전력 대폭 절감

---

## 4. 실측 벤치마크 및 쇼케이스 (Benchmark Showcase)

실제 웹 브라우징(Chromium/Gecko) 환경에서 배터리(`BAT1`) 방전 전력, CPU 패키지 온도, 실시간 클럭을 1~2분 단위로 정밀 샘플링하여 도출한 데이터입니다.

### 📊 배터리(DC) 모드 설정별 실측 비교표

| 설정 구성 | 코어 토폴로지 | 클럭 상한 | 평균 전력 | 바닥 전력 (Idle) | 피크 전력 | P코어 피크 | E코어 피크 | 평균 온도 | 평가 및 특성 |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **터보 ON (50%)** | 2P + 4E (6코어) | 50% 제한 | **15.10 W** | 12.24 W | 19.75 W | 2.30 GHz | 1.80 GHz | 44.0 °C | 고클럭 V/F 전압 급상승으로 전력 소모 큼 |
| **터보 OFF (100%)** | 2P + 4E (6코어) | 100% 베이스 | **14.07 W** | 12.60 W | 17.29 W | 2.01 GHz | 1.01 GHz | 43.6 °C | E코어 4개 1.0GHz 락으로 작업 지연 |
| **터보 ON (40%)** | 2P + 4E (6코어) | 40% 제한 | **12.72 W** | 9.26 W | 18.91 W | 2.01 GHz | 1.51 GHz | 46.2 °C | E코어 1.5GHz 반응성 확보, 4코어 한계로 피크 튐 |
| **터보 OFF (100%) [bal_power]** | 2P + 8E (10코어) | 100% 베이스 | **11.70 W** | 8.41 W | 16.95 W | 2.01 GHz | 1.01 GHz | 45.9 °C | 물리적 저클럭 다코어의 우위 (-3.4W 절감) |
| **터보 OFF (100%) + EPP power** | 2P + 8E (10코어) | 100% 베이스 | **10.16 W** | 7.13 W | 11.42 W | 2.01 GHz | 1.01 GHz | 44.0 °C | EPP power로 피크 스파이크 원천 억제 |
| **8E 전담 (60%) + CPU 0 격리 🏆** | **8E (CPU 8~15)** | **60% 제한 (~2.0GHz)** | **13.44 W** (CPU 5.4W) | **6.53 W** (CPU 2.9W) | **15.20 W** | **N/A (C10 격리)** | **2.00 GHz** | **42.0 °C** | **최종 선정**: P코어 원천 배제로 42°C 무소음 달성, 16 GHz·core 연산 여유 |

### 💡 핵심 아키텍처 발견 & 튜닝 인사이트

1. **E-코어 8개 전담 + CPU 0 식물인간 격리 아키텍처의 혁신**:
   - P-코어는 거대한 OOOE(비순차적 명령어 처리) 윈도우와 높은 커패시턴스로 인해 사소한 부하에도 국소 다이 온도를 50~60°C로 급상승시키고 팬 회전을 유발합니다.
   - CPU 0을 C10 딥슬립으로 격리하고 CPU 1~7을 오프라인한 뒤 8개 E-코어에 60% 터보(~2.0GHz)를 허용하면, 웹서핑+음악 재생 부하에서도 CPU 온도가 42.0°C에 고정되어 쿨링팬이 0 RPM으로 완벽히 정지합니다.
   - 단순 클럭 합산 기준 8코어 * 2.0GHz = 16.0 GHz·core로, 기존 2P(2.0GHz) + 8E(1.0GHz) = 12.0 GHz·core 대비 33% 이상 여유로운 연산력을 제공하면서도 열역학적 쾌적성과 배터리 지속 시간을 극대화합니다.

2. **"저클럭 다코어(8E @ 1.0GHz)" vs "고클럭 소수코어(4E @ 1.5GHz)"**:
   - 브라우저는 탭 하나만 열어도 JS V8 엔진, GC, 컴포지터, 네트워크 등 수십 개의 백그라운드 스레드를 생성합니다.
   - 4E 환경에서는 4개 코어에 부하가 몰려 스케줄러가 P코어를 자주 깨워 피크 전력이 18.9W까지 튑니다.
   - 반면 8E 환경에서는 8개 코어가 일감을 넉넉히 분산 처리하여 P코어 개입을 최소화하고, 피크와 바닥 전력을 모두 안정화합니다.

3. **하드웨어 에너지 정책(EPP)의 `power` 강제 효과**:
   - `powerprofilesctl set balanced` 실행 시 커널 기본값으로 복귀되는 EPP(`balance_power`)를 하드웨어 최저 전력 선호도인 `power`로 명시적 재설정.
   - 불필요한 고클럭 치솟음을 억제하고 깊은 C-state 진입을 극대화.

4. **AC/DC 단일 토폴로지 무지연 전환**:
   - 시스템 전체를 **[8E 전담 + CPU 0 격리]**로 단일화하여, 충전기 탈착 시 CPU Hotplug 오버헤드 없이 `intel_pstate` 레지스터 전환만으로 0.001초 만에 매끄럽게 전환됩니다.

---

## 5. 수동 확인 및 테스트 명령어

- **현재 CPU 코어 활성 상태 및 터보 상태 확인**:
  ```bash
  ~/Desktop/OneClickScripts/PowerOptions/check_status.sh
  ```
- **sysctl 커널 파라미터 확인**:
  ```bash
  sysctl vm.dirty_writeback_centisecs vm.laptop_mode
  ```

---

## 6. 롤백 (설정 원상 복구) 방법

```bash
# 1. sysctl 설정 제거
sudo rm -f /etc/sysctl.d/99-ssd-power-saving.conf
sudo sysctl --system

# 2. udev 룰 및 sudoers 제거
sudo rm -f /etc/udev/rules.d/99-power-profile-switch.rules
sudo rm -f /etc/sudoers.d/poweroptions
sudo udevadm control --reload

# 3. 자동 실행 및 스크립트 파일 제거
rm -f ~/.config/autostart/power-options-startup.desktop
rm -f ~/.config/autostart/disable-ht.desktop
rm -f ~/.local/bin/disable-ht.sh
rm -rf ~/Desktop/OneClickScripts/PowerOptions

# 4. 모든 CPU 코어 다시 켜기
for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
    echo 1 | sudo tee "$cpu/online" 2>/dev/null || true
done

# 5. Wi-Fi 설정 및 백그라운드 서비스/커서 복원
sudo rm -f /etc/modprobe.d/iwlwifi.conf
sudo systemctl unmask packagekit.service packagekit-offline-update.service
systemctl --user unmask gnome-software.service
gsettings set org.gnome.desktop.interface cursor-blink true
```
