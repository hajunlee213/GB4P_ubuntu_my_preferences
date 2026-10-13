# power_consumption.sh 설명 문서

이 문서는 **[`power_consumption.sh`](./power_consumption.sh)** 스크립트가 적용하는 패치 내용, 동작 원리, 설정 파일 및 롤백 방법을 상세히 설명합니다.

---

## 1. 배경 및 해결하려는 문제

삼성 갤럭시 북4 프로(GB4P, Intel Core Ultra 5 125H / Meteor Lake 아키텍처)는 고해상도 OLED 디스플레이와 다핵 하이브리드 CPU(4P + 8E + 2LP-E)를 탑재하고 있어 리눅스 우분투 기본 환경에서 다음과 같은 전력 및 발열 문제가 발생합니다:

1. **NVMe SSD의 잦은 웨이크업(Wakeup)으로 인한 배터리 소모**:
   - 리눅스 기본 커널 설정에서는 디스크 캐시 dirty writeback 주기가 5초 단위로 짧게 돌아가 SSD가 절전 상태(APST / NVMe low power state)에 머무르지 못하고 자주 깨어납니다.
2. **Meteor Lake 하이브리드 CPU의 고발열 및 타일 간 패브릭 전력 누수**:
   - P코어의 하이퍼스레딩(HT)과 터보 부스트 고전압 피크가 동작할 때 50~60°C 이상의 국소 열점(Hotspot)과 팬 소음이 발생합니다.
   - SoC Tile의 LP-E(CPU 16, 17) 코어는 Compute Tile(18MB L3)과 Foveros 3D 인터커넥트로 분리되어 있어, 리눅스에서 일감을 줄 때마다 크로스 타일 패브릭 트래픽과 캐시 미스로 인해 오히려 배터리 방전율이 상승(+0.17W Pkg, +1.2°C 발열)합니다.
3. **x86 BSP 제약과 CPU 0의 진화 (식물인간 격리 $\rightarrow$ 1.2GHz LPE 전담)**:
   - x86 아키텍처의 Bootstrap Processor(BSP) 특성상 CPU 0은 하드웨어 차원(`cpu0/online`)에서 오프라인을 지원하지 않습니다.
   - 초기에는 CPU 0을 `AllowedCPUs=8-15`로 격리하여 "식물인간"으로 두었으나, 8E 코어가 오디오 연산, Wi-Fi 인터럽트, 시스템 데몬까지 모두 떠안아 잦은 웨이크업 및 부하 집중이 발생했습니다.
   - **해결책**: 어차피 켜져 있어야 하는 CPU 0에 **터보 부스트를 끄고 1.2GHz 베이스 클럭 락(`scaling_max_freq=1200000`) 및 EPP `power`**를 적용하여 초절전 LPE 코어로 전환하고, 시스템 데몬/하드웨어 IRQ/오디오 처리를 전담시킴으로써 **전력 절감(-5.7% Pkg, -9.7% Core), 핫스팟 제거(-1.5°C), C10 체류율 2배 급증(63.2%)**을 달성했습니다.
4. **충전기(AC) 및 배터리(DC) 전환 시 수동 설정의 번거로움**:
   - 배터리(DC)와 충전기(AC) 연결 시 최적의 전성비 클럭 상한선(DC: 70% / AC: 80%)을 하드웨어 이벤트(udev)로 자동 감지/전환하는 시스템이 필요합니다.

---

## 2. 적용되는 설정 및 시스템 경로

이 스크립트는 다음 위치에 설정 파일 및 도구들을 배치합니다:

| 대상 경로 | 설명 | 원본 파일 위치 |
| :--- | :--- | :--- |
| `/etc/sysctl.d/99-ssd-power-saving.conf` | SSD 더티 페이지 쓰기 주기 지연 및 laptop_mode 설정 | [`configs/sysctl/99-ssd-power-saving.conf`](./configs/sysctl/99-ssd-power-saving.conf) |
| `/etc/udev/rules.d/99-power-profile-switch.rules` | AC/DC 전원 어댑터 연결/분리 이벤트 감지 udev 룰 | [`configs/udev/99-power-profile-switch.rules`](./configs/udev/99-power-profile-switch.rules) |
| `/etc/sudoers.d/poweroptions` | 전원 스크립트 실행 시 비밀번호 입력을 면제하는 sudoers 설정 | [`configs/sudoers/poweroptions`](./configs/sudoers/poweroptions) |
| `/etc/modprobe.d/iwlwifi.conf` | Intel Wi-Fi 모듈 초절전 모드 (power_save=1, power_level=5) | [`configs/modprobe/iwlwifi.conf`](./configs/modprobe/iwlwifi.conf) |
| `~/.local/bin/disable-ht.sh` | CPU 토폴로지 제어 (8E 전담 + CPU 0 1.2GHz LPE 전담 + IRQ 직결) | [`configs/bin/disable-ht.sh`](./configs/bin/disable-ht.sh) |
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

```
                      Compute Tile (18MB L3 공유 캐시)
 ┌────────────────────────────────────────────────────────────────────────┐
 │  [CPU 0: Redwood Cove P-Core (LPE 에뮬레이션)]                         │
 │  - 클럭: 1.2GHz 베이스 클럭 고정 (scaling_max_freq=1200000, EPP=power) │
 │  - 시스템 슬라이스: system.slice (OS 시스템 데몬 전담, AllowedCPUs=0)  │
 │  - 시스템 Init: init.scope (PID 1 systemd, AllowedCPUs=0)              │
 │  - 오디오 핀포인트: PipeWire, WirePlumber, pipewire-pulse (taskset -cp 0)│
 │  - 하드웨어 IRQ: AudioDSP (IRQ 200), Wi-Fi iwlwifi (IRQ 184~199)       │
 │  - 특징: 터보 차단으로 핫스팟 제거 (-1.5°C), 18MB L3 내부 초고속 완결, │
 │         단일 스레드 파이프라인으로 μs 단위 처리 후 C10 슬립(63.2%) 복귀│
 │                                                                        │
 │  [CPU 8~15: Crestmont 8E Cores (사용자 고부하 연산 전담)]              │
 │  - 클럭: 터보 부스트 ON (AC: 80% / DC: 70%, ~2.5~3.0GHz, EPP=power)    │
 │  - 사용자 슬라이스: user.slice, user-1000.slice (AllowedCPUs=8-15)    │
 │  - 담당: GNOME 셸, 브라우저, 렌더러, 비디오 디코더, 모든 사용자 프로그램│
 │  - 특징: 잡다한 인터럽트가 제거되어 16% 균일 C0 활성율 및 무소음 유지 │
 └────────────────────────────────────────────────────────────────────────┘
                                     ▲
                           Foveros 인터커넥트 동결
                                     ▼
                         SoC Tile (LP-E 코어 16, 17)
 ┌────────────────────────────────────────────────────────────────────────┐
 │  [CPU 1~7 (P-Core) & CPU 16, 17 (LP-E): 완전 Offline]                 │
 │  - 패브릭 통신 0, 크로스 타일 IPI 0                                    │
 └────────────────────────────────────────────────────────────────────────┘
```

1. **CPU 0 터보 차단 및 1.2GHz 베이스 클럭 락**:
   - `scaling_max_freq = 1200000` (1.2GHz) 및 `energy_performance_preference = power`를 강제.
   - P-Core의 3.6GHz+ 터보 부스트 고전압 급상승을 원천 차단하여 국소 핫스팟 발열 제거.
2. **cgroups v2 계층 슬라이스 분리**:
   - `systemctl set-property system.slice AllowedCPUs=0`: 시스템 데몬 전체를 CPU 0에 배정.
   - `systemctl set-property init.scope AllowedCPUs=0`: PID 1 systemd 프로세스를 CPU 0에 배정.
   - `systemctl set-property user.slice AllowedCPUs=8-15`: 브라우저, GUI 렌더러 등 사용자 프로그램이 1.2GHz CPU 0으로 누수되지 않도록 8E 코어로 완벽 격리.
3. **사용자 세션 오디오 데몬 핀포인트 차출 (`taskset -cp 0`)**:
   - 대상: `pipewire`, `wireplumber`, `pipewire-pulse`
   - 구조상 `user-1000.slice`에 속해 있으나, 실시간 PCM 오디오 믹싱과 버퍼 복사는 순수 짤짤이 I/O 연산이므로 `taskset`을 통해 CPU 0으로 직결.
4. **하드웨어 인터럽트(IRQ) CPU 0 직결 (`smp_affinity_list=0`)**:
   - 대상: AudioDSP (IRQ 200), Wi-Fi `iwlwifi` 큐 (IRQ 184~199)
   - 사운드 및 무선 칩셋의 하드웨어 인터럽트를 CPU 0에 직결하여 백그라운드 타이머 슬랙과 함께 효율적으로 일괄 처리.
5. **P-코어 (CPU 1~7) 및 LP-E (CPU 16, 17) 완전 오프라인**:
   - 고발열 OOOE P-코어를 차단하고, 캐시 미스와 패브릭 전력을 유발하는 SoC Tile LP-E를 꺼서 Compute Tile 내부로 아키텍처 단일화.

### (3) AC/DC 자동 전환 시스템 (`/etc/udev/rules.d/99-power-profile-switch.rules`)
- **🔌 충전기(AC) 연결 시**: 터보 부스트 ON (80% 클럭 제한 / E-코어 ~3.0GHz * 8개) + 절전 모드(Power Saver) + EPP `power`
  - CPU 0은 1.2GHz 락 유지, 총 24.0 GHz·core 연산력 제공, 무소음/고성능 유지.
- **🔋 배터리(DC) 전환 시**: 터보 부스트 ON (70% 클럭 제한 / E-코어 ~2.5GHz * 8개) + 절전 모드(Power Saver) + EPP `power`
  - CPU 0은 1.2GHz 락 유지, 총 20.0 GHz·core 연산력 제공, 전성비 최적 구간으로 저발열/무소음 유지.

### (4) 전력 최적화 고급 튜닝
- **커서 깜빡임 차단 (`cursor-blink = false`)**: eDP 패널의 `PSR2 SLEEP` 및 GPU RC6 딥슬립 유지.
- **PackageKit unmask 보장**: App Center 'Manage' 탭 정상 동작 유지.
- **Intel Workload Type Hints 활성화 (`workload_hint_enable = 1`)**: 메테오레이크 하드웨어 워크로드 감지 기능.
- **Intel Wi-Fi 초절전 파라미터 (`/etc/modprobe.d/iwlwifi.conf`)**: `power_save=1 power_level=5`.

---

## 4. 실측 벤치마크 및 쇼케이스 (Benchmark Showcase)

`CORE-TOPOLOGY-TEST-261008`에서 각 30초, 1초 주기 RAPL/C-State 정밀 샘플링으로 검증한 실측 데이터입니다.

### Part 1: SoC Tile LP-E 코어 분산 실패 분석

| 시나리오 | 구분 | CPU 코어 전력 | CPU 패키지 전력 | 배터리 전체 방전율 | 패키지 온도 | 판정 |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **1. 일반 유휴/경부하** | **8E 단일 (LPE OFF)**<br>하이브리드 (8E + LPE) | **2.63 W**<br>2.65 W | **5.91 W**<br>5.95 W | **10.42 W**<br>11.12 W | **48.1 °C**<br>48.3 °C | **8E 단일 승** |
| **2. 순수 Idle (화면 정지)** | **8E 단일 (LPE OFF)**<br>하이브리드 (8E + LPE) | **0.34 W (-17%)**<br>0.41 W | **2.47 W (-8%)**<br>2.67 W | **4.18 W (-18%)**<br>5.08 W | **42.1 °C**<br>42.3 °C | **8E 단일 압승 (-0.90W)** |
| **3. 미디어 스트리밍 (유튜브)** | **8E 단일 (LPE OFF)**<br>하이브리드 (8E + LPE) | **3.24 W (-4%)**<br>3.37 W | **6.97 W (-2.4%)**<br>7.14 W | **13.50 W (-2.5%)**<br>13.84 W | **48.1 °C**<br>49.3 °C (+1.2°C) | **8E 단일 승 (-0.34W)** |

> **원인 (`CAUSE=`)**: Compute Tile(8E)과 SoC Tile(LP-E) 간의 IPC 교환 시 Foveros 패브릭 인터커넥트 상시 가동 비용과 L3 부재로 인한 메인 메모리(LPDDR5) 버스 경유 전력 손실이 코어 절전 이득을 완전히 상쇄함.

---

### Part 2: 최종 A/B 챔피언십 [8E 단순형] vs [CPU 0 1.2GHz LPE 전담]

유튜브 1080p 영상+사운드 스트리밍 재생 중 동일 조건 30초 정밀 실측 결과:

| 측정 항목 | Phase A: 8E 단순형<br>(CPU 0 식물인간 격리) | Phase B: CPU 0 LPE 전담 @ 1.2GHz<br>(8E Apps + CPU 0 System/Audio/IRQ) | 변동폭 ($\Delta$)<br>(Phase B 최종 선정) |
| :--- | :---: | :---: | :---: |
| **CPU 코어 순수 전력 (RAPL Core)** | **2.57 W** (2.01 ~ 3.38 W) | **2.32 W** (1.96 ~ 3.16 W) | **-0.25 W (-9.7% 절감)** |
| **CPU 패키지 전체 전력 (RAPL Pkg)** | **6.30 W** (5.53 ~ 7.64 W) | **5.94 W** (5.46 ~ 7.13 W) | **-0.36 W (-5.7% 절감)** |
| **CPU 패키지 평균 온도** | **49.6 °C** | **48.1 °C** | **-1.5 °C (핫스팟 해소)** |
| **CPU 0 C10 딥슬립 체류율** | 30.05 % | **63.22 %** | **+33.17 % (2배 이상 증가)** |
| **CPU 0 활성율 (C0 Active)** | 3.00 % | **2.37 %** | -0.63 % |
| **8E 코어(8~15) 평균 활성율** | 18.2 % (부하 쏠림 존재) | **16.6 % (균일하게 분산)** | 인터럽트 병목 해소 |

### 핵심 아키텍처 발견 & 튜닝 인사이트
1. **18MB L3 내부 초고속 완결**:
   - 브라우저 $\leftrightarrow$ PipeWire $\leftrightarrow$ Wi-Fi 드라이버 간의 모든 IPC 데이터 교환이 Compute Tile 18MB L3 공유 캐시 내부에서 0-인터커넥트 오버헤드로 완결.
2. **1.2GHz 클럭 락으로 국소 열점(-1.5°C) 제거**:
   - CPU 0의 터보 부스트를 원천 차단하여 P-Core 특유의 고전압 스파이크를 없애고 다이 전체 온도를 48.1°C로 하강.
3. **C10 딥슬립 극대화 (30% $\rightarrow$ 63.2%)**:
   - P-Core의 단일 스레드 연산력으로 1.2GHz에서도 자잘한 인터럽트를 수 μs 만에 신속 처리 후 즉시 C10 슬립으로 복귀.

---

## 5. 수동 확인 및 테스트 명령어

- **현재 CPU 코어 활성 상태 및 터보 상태 확인**:
  ```bash
  ~/Desktop/OneClickScripts/PowerOptions/check_status.sh
  ```
- **CPU 0 클럭 상한선 및 EPP 확인**:
  ```bash
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
  cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference
  ```
- **cgroups v2 슬라이스별 AllowedCPUs 확인**:
  ```bash
  systemctl show system.slice -p AllowedCPUs
  systemctl show user.slice -p AllowedCPUs
  ```
- **오디오 데몬 및 IRQ 친화도 확인**:
  ```bash
  taskset -cp $(pgrep -x pipewire | head -n 1)
  cat /proc/irq/200/smp_affinity_list
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

# 4. cgroups v2 슬라이스 격리 해제
sudo systemctl set-property system.slice AllowedCPUs=
sudo systemctl set-property init.scope AllowedCPUs=
sudo systemctl set-property user.slice AllowedCPUs=
sudo systemctl set-property user-1000.slice AllowedCPUs=

# 5. 모든 CPU 코어 다시 켜기 및 클럭 캡 해제
for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
    echo 1 | sudo tee "$cpu/online" 2>/dev/null || true
done
for f in /sys/devices/system/cpu/cpu*/cpufreq; do
    [ -f "$f/cpuinfo_max_freq" ] && cat "$f/cpuinfo_max_freq" | sudo tee "$f/scaling_max_freq" 2>/dev/null || true
done

# 6. IRQ 친화도 복원 (모든 코어로 개방)
for irq in $(grep -E "iwlwifi|snd_hda_intel|sof" /proc/interrupts 2>/dev/null | awk '{print $1}' | tr -d ':'); do
    [ -f "/proc/irq/$irq/smp_affinity_list" ] && echo 0-15 | sudo tee "/proc/irq/$irq/smp_affinity_list" 2>/dev/null || true
done

# 7. Wi-Fi 설정 및 백그라운드 서비스/커서 복원
sudo rm -f /etc/modprobe.d/iwlwifi.conf
sudo systemctl unmask packagekit.service packagekit-offline-update.service
systemctl --user unmask gnome-software.service
gsettings set org.gnome.desktop.interface cursor-blink true
```
